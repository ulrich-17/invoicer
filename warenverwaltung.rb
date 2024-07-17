require 'gtk3'
require 'prawn'
require 'prawn/table'
require 'sqlite3'

# Datenbank einrichten
DATABASE = SQLite3::Database.new 'rechnungen.db'
DATABASE.execute <<-SQL
  CREATE TABLE IF NOT EXISTS rechnungen (
    id INTEGER PRIMARY KEY,
    kunde INTEGER,
    summe REAL,
    datum TEXT,
    bezahlt BOOLEAN
  );
SQL

DATABASE.execute(<<-SQL)
CREATE TABLE IF NOT EXISTS rechnungspositionen (
    id INTEGER PRIMARY KEY,
    rechnung_id INTEGER,
    produkt_id INTEGER,
    menge INTEGER,
    einzelpreis_netto REAL,
    mwst_satz REAL,
    einzelpreis_brutto REAL,
    gesamtpreis_netto REAL,
    gesamtpreis_brutto REAL,
    mwst_betrag REAL
  )
SQL

DATABASE.execute <<-SQL
  CREATE TABLE IF NOT EXISTS kunden (
    id INTEGER PRIMARY KEY,
    name TEXT,
    strasse TEXT,
    hausnummer TEXT,
    plz TEXT,
    stadt TEXT,
    email TEXT,
    telefon TEXT
  );
SQL

DATABASE.execute <<-SQL
  CREATE TABLE IF NOT EXISTS produkte (
    id INTEGER PRIMARY KEY,
    name TEXT,
    preis REAL,
    lagerstand INTEGER,
    mwst_satz REAL,
    can_sell BOOLEAN DEFAULT TRUE
  );
SQL

class RechnungApp
  def initialize
    @window = Gtk::Window.new
    @window.set_title("Rechnungen, Waren und Kunden")
    @window.set_default_size(800, 600)
    @window.signal_connect('destroy') { Gtk.main_quit }

    # Initialize @list_store
    @list_store = Gtk::ListStore.new(Integer, String, Float, String, Integer)

    vbox = Gtk::Box.new(:vertical, 5)
    @window.add(vbox)

    menubar = Gtk::MenuBar.new
    file_menu = Gtk::Menu.new
    manage_menu = Gtk::Menu.new
    customer_menu = Gtk::Menu.new
    product_menu = Gtk::Menu.new

    file_item = Gtk::MenuItem.new(label: 'Datei')
    file_item.set_submenu(file_menu)

    product_item = Gtk::MenuItem.new(label: 'Produkte')
    product_item.set_submenu(product_menu)

    add_product_item = Gtk::MenuItem.new(label: 'Produkt hinzufügen')
    add_product_item.signal_connect('activate') { add_product }

    edit_product_item = Gtk::MenuItem.new(label: 'Produkt bearbeiten')
    edit_product_item.signal_connect('activate') { edit_product }

    inventory_item = Gtk::MenuItem.new(label: 'Lagerbestand anzeigen')
    inventory_item.signal_connect('activate') { show_inventory }

    manage_item = Gtk::MenuItem.new(label: 'Rechnungen')
    manage_item.set_submenu(manage_menu)

    customer_item = Gtk::MenuItem.new(label: 'Kunden')
    customer_item.set_submenu(customer_menu)

    exit_item = Gtk::MenuItem.new(label: 'Beenden')
    exit_item.signal_connect('activate') { Gtk.main_quit }

    add_customer_item = Gtk::MenuItem.new(label: 'Kunden hinzufügen')
    add_customer_item.signal_connect('activate') { add_customer }

    delete_customer_item = Gtk::MenuItem.new(label: 'Kunden löschen')
    delete_customer_item.signal_connect('activate') { delete_customer }

    edit_customer_item = Gtk::MenuItem.new(label: "Kunden bearbeiten")
    edit_customer_item.signal_connect('activate') { edit_customer }

    create_invoice_item = Gtk::MenuItem.new(label: 'Rechnung erstellen')
    create_invoice_item.signal_connect('activate') { create_invoice }

    recreate_pdf_item = Gtk::MenuItem.new(label: 'PDF erneut erstellen')
    recreate_pdf_item.signal_connect('activate') { recreate_pdf }

    delete_invoice_item = Gtk::MenuItem.new(label: 'Rechnung löschen')
    delete_invoice_item.signal_connect('activate') { delete_invoice }

    show_invoices_item = Gtk::MenuItem.new(label: 'Rechnungen anzeigen')
    show_invoices_item.signal_connect('activate') { show_invoices }

    file_menu.append(exit_item)
    manage_menu.append(create_invoice_item)
    manage_menu.append(delete_invoice_item)
    manage_menu.append(recreate_pdf_item)
    manage_menu.append(show_invoices_item)
    customer_menu.append(add_customer_item)
    customer_menu.append(delete_customer_item)
    customer_menu.append(edit_customer_item)
    product_menu.append(add_product_item)
    product_menu.append(inventory_item)
    product_menu.append(edit_product_item)

    menubar.append(file_item)
    menubar.append(manage_item)
    menubar.append(customer_item)
    menubar.append(product_item)

    vbox.pack_start(menubar, expand: false, fill: false, padding: 0)

    # Hauptinhaltsbereich erstellen und hinzufügen
    @main_content_area = Gtk::Box.new(:vertical, 5)
    vbox.pack_start(@main_content_area, expand: true, fill: true, padding: 0)

    @window.show_all
  end

  def clear_main_content_area
    @main_content_area.children.each { |child| @main_content_area.remove(child) }
  end



  # Methode zum Aktualisieren der Statusleiste
  def update_status(message)
    @statusbar.push(0, message)
    puts message  # Optional: Behalten Sie die Konsolenausgabe bei
  end

  def search_invoices(query)
    @list_store.clear
    if query.empty?
      load_last_10_invoices
    else
      DATABASE.execute('SELECT rechnungen.id, kunden.name, rechnungen.summe, rechnungen.datum, rechnungen.bezahlt
                      FROM rechnungen
                      JOIN kunden ON rechnungen.kunde = kunden.id
                      WHERE kunden.name LIKE ? OR rechnungen.datum LIKE ?',
                       ["%#{query}%", "%#{query}%"]) do |row|
        @list_store.append.set_values([row[0], row[1], row[2], row[3], row[4] == 1 ? 'Ja' : 'Nein'])
      end
    end
  end

  def load_last_10_invoices
    @list_store.clear
    DATABASE.execute('SELECT rechnungen.id, kunden.name, rechnungen.summe, rechnungen.datum, rechnungen.bezahlt
                    FROM rechnungen
                    JOIN kunden ON rechnungen.kunde = kunden.id
                    ORDER BY rechnungen.id DESC LIMIT 10') do |row|
      @list_store.append.set_values([row[0], row[1], row[2], row[3], row[4] == 1 ? 'Ja' : 'Nein'])
    end
  end

  def open_load_dialog
    dialog = Gtk::Dialog.new(
      title: "Rechnung laden",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['OK', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area
    rechnungen_combo = Gtk::ComboBoxText.new
    DATABASE.execute('SELECT id, kunde FROM rechnungen') do |row|
      rechnungen_combo.append(row[0].to_s, row[1])
    end
    dialog_content_area.add(Gtk::Label.new("Rechnung auswählen:"))
    dialog_content_area.add(rechnungen_combo)
    dialog_content_area.show_all

    response = dialog.run
    if response == :ok
      id = rechnungen_combo.active_id.to_i
      load_data(id)
    end

    dialog.destroy
  end
  def show_invoices
    clear_main_content_area

    # TreeView für Rechnungen
    treeview = Gtk::TreeView.new
    renderer = Gtk::CellRendererText.new
    columns = ['ID', 'Kunde', 'Summe', 'Datum', 'Bezahlt']
    list_store = Gtk::ListStore.new(Integer, String, Float, String, String)

    columns.each_with_index do |col, idx|
      column = Gtk::TreeViewColumn.new(col, renderer, text: idx)
      treeview.append_column(column)
    end
    treeview.model = list_store

    treeview.signal_connect('row-activated') do |view, path, column|
      iter = list_store.get_iter(path)
      id = iter[0]
      edit_invoice(id)
    end

    @main_content_area.pack_start(treeview, expand: true, fill: true, padding: 0)
    load_rechnungen_to_list_store(list_store)

    @main_content_area.show_all
  end

  def edit_invoice(id)
    invoice_data = DATABASE.execute('SELECT kunde, summe, datum, bezahlt FROM rechnungen WHERE id = ?', id).first
    customer_id, total_sum, date, paid = invoice_data

    dialog = Gtk::Dialog.new(
      title: "Rechnung bearbeiten",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['Speichern', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area

    # Kunde auswählen
    customer_combo = Gtk::ComboBoxText.new
    DATABASE.execute('SELECT id, name FROM kunden') do |row|
      customer_combo.append(row[0].to_s, row[1])
    end
    customer_combo.active_id = customer_id.to_s
    dialog_content_area.add(Gtk::Label.new("Kunde:"))
    dialog_content_area.add(customer_combo)

    # Summe
    sum_entry = Gtk::Entry.new
    sum_entry.text = total_sum.to_s
    dialog_content_area.add(Gtk::Label.new("Summe:"))
    dialog_content_area.add(sum_entry)

    # Datum
    date_entry = Gtk::Entry.new
    date_entry.text = date
    dialog_content_area.add(Gtk::Label.new("Datum:"))
    dialog_content_area.add(date_entry)

    # Bezahlt
    paid_check = Gtk::CheckButton.new("Bezahlt")
    paid_check.active = (paid == 1)
    dialog_content_area.add(paid_check)

    dialog_content_area.show_all

    response = dialog.run
    if response == :ok
      new_customer_id = customer_combo.active_id.to_i
      new_sum = sum_entry.text.to_f
      new_date = date_entry.text
      new_paid = paid_check.active? ? 1 : 0

      DATABASE.execute("UPDATE rechnungen SET kunde = ?, summe = ?, datum = ?, bezahlt = ? WHERE id = ?",
                       [new_customer_id, new_sum, new_date, new_paid, id])
      load_rechnungen_to_list_store(@list_store)
      update_status "Rechnung aktualisiert"
    end

    dialog.destroy
  end


  def delete_invoice
    dialog = Gtk::Dialog.new(
      title: "Rechnung löschen",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['OK', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area
    invoice_combo = Gtk::ComboBoxText.new
    DATABASE.execute('SELECT id, datum, summe FROM rechnungen') do |row|
      invoice_combo.append(row[0].to_s, "Rechnung #{row[0]} vom #{row[1]} (#{row[2]} €)")
    end
    dialog_content_area.add(Gtk::Label.new("Rechnung auswählen:"))
    dialog_content_area.add(invoice_combo)
    dialog_content_area.show_all

    response = dialog.run
    if response == :ok
      id = invoice_combo.active_id.to_i
      if id > 0
        DATABASE.execute('DELETE FROM rechnungen WHERE id = ?', id)
        puts "Rechnung gelöscht"
        load_rechnungen_to_list_store(@list_store)
      else
        puts "Keine gültige Rechnung ausgewählt"
      end
    end

    dialog.destroy
  end

def recreate_pdf
  selected = @treeview.selection.selected
  if selected
    invoice_id = selected[0]

    # Hole die Rechnungsdaten aus der Datenbank
    invoice_data = DATABASE.execute("SELECT rechnungen.*, kunden.* FROM rechnungen
                                     JOIN kunden ON rechnungen.kunde = kunden.id
                                     WHERE rechnungen.id = ?", invoice_id).first

    if invoice_data
      # Extrahiere die benötigten Daten
      customer_id = invoice_data[1]
      total_sum = invoice_data[2]
      invoice_date = invoice_data[3]

      # Hole die Produktdaten für diese Rechnung
      products = DATABASE.execute("SELECT produkte.id, produkte.name, rechnungspositionen.einzelpreis_brutto, rechnungspositionen.menge
                                   FROM rechnungspositionen
                                   JOIN produkte ON rechnungspositionen.produkt_id = produkte.id
                                   WHERE rechnungspositionen.rechnung_id = ?", invoice_id)

      # Berechne die Gesamtmehrwertsteuer
      total_mwst = DATABASE.execute("SELECT SUM(mwst_betrag) FROM rechnungspositionen WHERE rechnung_id = ?", invoice_id).first[0]

      # Bereite die selected_products für generate_pdf vor
      selected_products = products.map { |p| [p[0], p[1], p[2], p[3]] }

      # Generiere das PDF
      generate_pdf(invoice_id, customer_id, selected_products, total_sum, total_mwst, invoice_date)

      update_status "PDF für Rechnung #{invoice_id} wurde neu erstellt"
    else
      update_status "Fehler: Rechnungsdaten nicht gefunden"
    end
  else
    update_status "Bitte wählen Sie eine Rechnung aus"
  end
end

  def load_data(id)
    data = DATABASE.execute('SELECT kunde, summe, datum, bezahlt FROM rechnungen WHERE id = ?', id).first

    if data
      puts "Rechnung geladen:"
      puts "Kunde: #{data[0]}"
      puts "Summe: #{data[1]}"
      puts "Datum: #{data[2]}"
      puts "Bezahlt: #{data[3] == 1 ? 'Ja' : 'Nein'}"
    else
      puts "Rechnung nicht gefunden"
    end
  end

  def delete_data
    dialog = Gtk::Dialog.new(
      title: "Rechnung löschen",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['OK', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area
    rechnungen_combo = Gtk::ComboBoxText.new
    DATABASE.execute('SELECT id, kunde FROM rechnungen') do |row|
      rechnungen_combo.append(row[0].to_s, row[1])
    end
    dialog_content_area.add(Gtk::Label.new("Rechnung auswählen:"))
    dialog_content_area.add(rechnungen_combo)
    dialog_content_area.show_all

    response = dialog.run
    if response == :ok
      id = rechnungen_combo.active_id.to_i
      DATABASE.execute('DELETE FROM rechnungen WHERE id = ?', id)
      load_rechnungen_to_list_store(@list_store)
      puts "Rechnung gelöscht"
    end

    dialog.destroy
  end

  def add_customer
    dialog = Gtk::Dialog.new(
      title: "Kunden hinzufügen",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['OK', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area

    # Erstellen Sie Eingabefelder für alle Kundeninformationen
    name_entry = Gtk::Entry.new
    strasse_entry = Gtk::Entry.new
    hausnummer_entry = Gtk::Entry.new
    plz_entry = Gtk::Entry.new
    stadt_entry = Gtk::Entry.new
    email_entry = Gtk::Entry.new
    telefon_entry = Gtk::Entry.new

    # Fügen Sie Labels und Eingabefelder zum Dialog hinzu
    [
      ["Name:", name_entry],
      ["Straße:", strasse_entry],
      ["Hausnummer:", hausnummer_entry],
      ["PLZ:", plz_entry],
      ["Stadt:", stadt_entry],
      ["E-Mail:", email_entry],
      ["Telefon:", telefon_entry]
    ].each do |label, entry|
      hbox = Gtk::Box.new(:horizontal, 5)
      hbox.pack_start(Gtk::Label.new(label), expand: false, fill: false, padding: 0)
      hbox.pack_start(entry, expand: true, fill: true, padding: 0)
      dialog_content_area.add(hbox)
    end

    dialog_content_area.show_all

    response = dialog.run
    if response == :ok
      name = name_entry.text
      strasse = strasse_entry.text
      hausnummer = hausnummer_entry.text
      plz = plz_entry.text
      stadt = stadt_entry.text
      email = email_entry.text
      telefon = telefon_entry.text

      DATABASE.execute(
        "INSERT INTO kunden (name, strasse, hausnummer, plz, stadt, email, telefon) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [name, strasse, hausnummer, plz, stadt, email, telefon]
      )

      update_status "Kunde hinzugefügt"
    end

    dialog.destroy
  end

  def edit_customer
    dialog = Gtk::Dialog.new(
      title: "Kunden bearbeiten",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['OK', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area

    # Kunden auswählen
    customer_combo = Gtk::ComboBoxText.new
    DATABASE.execute('SELECT id, name FROM kunden') do |row|
      customer_combo.append(row[0].to_s, row[1])
    end
    dialog_content_area.add(Gtk::Label.new("Kunden auswählen:"))
    dialog_content_area.add(customer_combo)

    # Eingabefelder für Kundeninformationen
    name_entry = Gtk::Entry.new
    strasse_entry = Gtk::Entry.new
    hausnummer_entry = Gtk::Entry.new
    plz_entry = Gtk::Entry.new
    stadt_entry = Gtk::Entry.new
    email_entry = Gtk::Entry.new
    telefon_entry = Gtk::Entry.new

    entries = [name_entry, strasse_entry, hausnummer_entry, plz_entry, stadt_entry, email_entry, telefon_entry]
    labels = ["Name:", "Straße:", "Hausnummer:", "PLZ:", "Stadt:", "E-Mail:", "Telefon:"]

    entries.each_with_index do |entry, index|
      hbox = Gtk::Box.new(:horizontal, 5)
      hbox.pack_start(Gtk::Label.new(labels[index]), expand: false, fill: false, padding: 0)
      hbox.pack_start(entry, expand: true, fill: true, padding: 0)
      dialog_content_area.add(hbox)
    end

    # Lade Kundendaten, wenn ein Kunde ausgewählt wird
    customer_combo.signal_connect('changed') do
      id = customer_combo.active_id.to_i
      data = DATABASE.execute('SELECT name, strasse, hausnummer, plz, stadt, email, telefon FROM kunden WHERE id = ?', id).first
      entries.each_with_index do |entry, index|
        entry.text = data[index].to_s
      end
    end

    dialog_content_area.show_all

    response = dialog.run
    if response == :ok
      id = customer_combo.active_id.to_i
      name = name_entry.text
      strasse = strasse_entry.text
      hausnummer = hausnummer_entry.text
      plz = plz_entry.text
      stadt = stadt_entry.text
      email = email_entry.text
      telefon = telefon_entry.text

      DATABASE.execute(
        "UPDATE kunden SET name = ?, strasse = ?, hausnummer = ?, plz = ?, stadt = ?, email = ?, telefon = ? WHERE id = ?",
        [name, strasse, hausnummer, plz, stadt, email, telefon, id]
      )
      puts "Kunde aktualisiert"
    end

    dialog.destroy
  end

  def delete_customer
    dialog = Gtk::Dialog.new(
      title: "Kunden löschen",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['OK', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area
    customer_combo = Gtk::ComboBoxText.new
    DATABASE.execute('SELECT id, name FROM kunden') do |row|
      customer_combo.append(row[0].to_s, row[1])
    end
    dialog_content_area.add(Gtk::Label.new("Kunden auswählen:"))
    dialog_content_area.add(customer_combo)
    dialog_content_area.show_all

    response = dialog.run
    if response == :ok
      id = customer_combo.active_id.to_i
      DATABASE.execute('DELETE FROM kunden WHERE id = ?', id)
      puts "Kunde gelöscht"
    end

    dialog.destroy
  end

  def add_product
    dialog = Gtk::Dialog.new(
      title: "Produkt hinzufügen",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [
        ['OK', :ok],
        ['Abbrechen', :cancel]
      ]
    )

    dialog_content_area = dialog.content_area
    name_entry = Gtk::Entry.new
    price_entry = Gtk::Entry.new
    stock_entry = Gtk::Entry.new
    stock_checkbox = Gtk::CheckButton.new("Lagerstand erfassen")
    mwst_entry = Gtk::Entry.new

    dialog_content_area.add(Gtk::Label.new("Produktname:"))
    dialog_content_area.add(name_entry)
    dialog_content_area.add(Gtk::Label.new("Preis (inkl. MwSt):"))
    dialog_content_area.add(price_entry)
    dialog_content_area.add(Gtk::Label.new("MwSt-Satz (%):"))
    dialog_content_area.add(mwst_entry)
    dialog_content_area.add(stock_checkbox)
    dialog_content_area.add(stock_entry)

    stock_checkbox.signal_connect('toggled') do |widget|
      stock_entry.sensitive = widget.active?
    end

    stock_entry.sensitive = false
    dialog_content_area.show_all

    # Checkbbox ob ein Produkt verkauft werdne kann oder nicht.
    can_sell_checkbox = Gtk::CheckButton.new("Kann verkauft werden")
    can_sell_checkbox.active = true
    dialog_content_area.add(can_sell_checkbox)

    response = dialog.run
    if response == :ok
      name = name_entry.text
      price = price_entry.text.to_f
      mwst_satz = mwst_entry.text.to_f
      stock = stock_checkbox.active? ? stock_entry.text.to_i : nil

      can_sell = can_sell_checkbox.active? ? 1 : 0

      if stock.nil?
        DATABASE.execute("INSERT INTO produkte (name, preis, mwst_satz) VALUES (?, ?, ?)", [name, price, mwst_satz])
      else
        DATABASE.execute("INSERT INTO produkte (name, preis, mwst_satz, lagerstand, can_sell) VALUES (?, ?, ?, ?, ?)", [name, price, mwst_satz, stock, can_sell])
      end
      update_status "Produkt hinzugefügt"
    end

    dialog.destroy
  end

  def edit_product
  dialog = Gtk::Dialog.new(
    title: "Produkt bearbeiten",
    parent: @window,
    flags: :destroy_with_parent,
    buttons: [
      ['OK', :ok],
      ['Abbrechen', :cancel]
    ]
  )

  dialog_content_area = dialog.content_area

  # Produkt auswählen
  product_combo = Gtk::ComboBoxText.new
  DATABASE.execute('SELECT id, name FROM produkte') do |row|
    product_combo.append(row[0].to_s, row[1])
  end
  dialog_content_area.add(Gtk::Label.new("Produkt auswählen:"))
  dialog_content_area.add(product_combo)

  # Eingabefelder für Produktinformationen
  name_entry = Gtk::Entry.new
  price_entry = Gtk::Entry.new
  stock_entry = Gtk::Entry.new
  mwst_entry = Gtk::Entry.new
  can_sell_checkbox = Gtk::CheckButton.new("Kann verkauft werden")

  entries = [name_entry, price_entry, stock_entry, mwst_entry]
  labels = ["Name:", "Preis (inkl. MwSt):", "Lagerbestand:", "MwSt-Satz (%):"]

  entries.each_with_index do |entry, index|
    hbox = Gtk::Box.new(:horizontal, 5)
    hbox.pack_start(Gtk::Label.new(labels[index]), expand: false, fill: false, padding: 0)
    hbox.pack_start(entry, expand: true, fill: true, padding: 0)
    dialog_content_area.add(hbox)
  end

  dialog_content_area.add(can_sell_checkbox)

  # Lade Produktdaten, wenn ein Produkt ausgewählt wird
  product_combo.signal_connect('changed') do
    id = product_combo.active_id.to_i
    data = DATABASE.execute('SELECT name, preis, lagerstand, mwst_satz, can_sell FROM produkte WHERE id = ?', id).first
    name_entry.text = data[0].to_s
    price_entry.text = data[1].to_s
    stock_entry.text = data[2].to_s
    mwst_entry.text = data[3].to_s
    can_sell_checkbox.active = data[4] == 1
  end

  dialog_content_area.show_all

  response = dialog.run
  if response == :ok
    id = product_combo.active_id.to_i
    name = name_entry.text
    price = price_entry.text.to_f
    stock = stock_entry.text.to_i
    mwst_satz = mwst_entry.text.to_f
    can_sell = can_sell_checkbox.active? ? 1 : 0

    DATABASE.execute(
      "UPDATE produkte SET name = ?, preis = ?, lagerstand = ?, mwst_satz = ?, can_sell = ? WHERE id = ?",
      [name, price, stock, mwst_satz, can_sell, id]
    )
    puts "Produkt aktualisiert"
  end

  dialog.destroy
end

def show_inventory
  puts "Starte show_inventory Methode"

  # Entfernen Sie alle Kinder des Hauptinhaltsbereichs
  @main_content_area.children.each { |child| @main_content_area.remove(child) }

  # Erstellen Sie ein TreeView für den Lagerbestand
  inventory_store = Gtk::ListStore.new(String, String, String)  # Alle Spalten als String
  inventory_view = Gtk::TreeView.new
  inventory_view.model = inventory_store

  # Fügen Sie Spalten hinzu
  renderer = Gtk::CellRendererText.new
  inventory_view.append_column(Gtk::TreeViewColumn.new("Produkt", renderer, text: 0))
  inventory_view.append_column(Gtk::TreeViewColumn.new("Lagerbestand", renderer, text: 1))
  inventory_view.append_column(Gtk::TreeViewColumn.new("Preis", renderer, text: 2))

  # Fügen Sie das TreeView zum Hauptinhaltsbereich hinzu
  scrolled_window = Gtk::ScrolledWindow.new
  scrolled_window.set_policy(:automatic, :automatic)
  scrolled_window.add(inventory_view)
  scrolled_window.set_vexpand(true)  # Ermöglicht vertikale Expansion
  scrolled_window.set_hexpand(true)  # Ermöglicht horizontale Expansion

  @main_content_area.add(scrolled_window)

  # Laden Sie die Daten aus der Datenbank
  begin
    puts "Starte Datenbankabfrage"
    DATABASE.execute('SELECT name, lagerstand, preis FROM produkte') do |row|
      puts "Gefundenes Produkt: #{row[0]}, Lagerbestand: #{row[1]}, Preis: #{row[2]}"
      # Konvertieren Sie alle Werte zu Strings und ersetzen Sie nil durch einen leeren String
      values = row.map { |value| value.nil? ? "" : value.to_s }
      inventory_store.append.set_values(values)
    end
    puts "Datenbankabfrage abgeschlossen"
  rescue SQLite3::Exception => e
    puts "Fehler beim Laden der Produkte: #{e.message}"
  end

  @main_content_area.show_all
  puts "show_inventory Methode beendet"
end

  def adjust_stock(selected_products)
    selected_products.each do |product|
      if product[:lagerstand]
        new_stock = product[:lagerstand] - product[:quantity].text.to_i
        new_stock = 0 if new_stock < 0
        DATABASE.execute("UPDATE produkte SET lagerstand = ? WHERE id = ?", [new_stock, product[:id]])
      end
    end
  end

def create_invoice
  dialog = Gtk::Dialog.new(
    title: "Rechnung erstellen",
    parent: @window,
    flags: :destroy_with_parent,
    buttons: [
      ['OK', :ok],
      ['Abbrechen', :cancel]
    ]
  )

  dialog_content_area = dialog.content_area

  # Kunde auswählen
  customer_combo = Gtk::ComboBoxText.new
  DATABASE.execute('SELECT id, name FROM kunden') do |row|
    customer_combo.append(row[0].to_s, row[1])
  end
  dialog_content_area.add(Gtk::Label.new("Kunde auswählen:"))
  dialog_content_area.add(customer_combo)

  # Produkte auswählen
  products_list = Gtk::ListBox.new
  products = []

  DATABASE.execute('SELECT id, name, preis, lagerstand, mwst_satz FROM produkte WHERE can_sell = 1') do |row|
    row_box = Gtk::Box.new(:horizontal, 10)
    checkbox = Gtk::CheckButton.new("#{row[1]} - #{row[2]} EUR (Lager: #{row[3] || 'N/A'})")
    quantity_entry = Gtk::Entry.new
    quantity_entry.width_chars = 3
    quantity_entry.text = "0"  # Standardwert auf 0 setzen

    # Signal für die Checkbox
    checkbox.signal_connect('toggled') do |widget|
      if widget.active?
        quantity_entry.text = "1" if quantity_entry.text.to_i == 0  # Setze auf 1, wenn es 0 ist
      else
        quantity_entry.text = "0"  # Setze auf 0, wenn die Checkbox deaktiviert wird
      end
    end

    # Signal für das Eingabefeld
    quantity_entry.signal_connect('changed') do |widget|
      if widget.text.to_i > 0
        checkbox.active = true
      else
        checkbox.active = false
      end
    end

    row_box.pack_start(checkbox, expand: false, fill: false, padding: 0)
    row_box.pack_start(quantity_entry, expand: false, fill: false, padding: 0)
    products_list.add(row_box)
    products << { id: row[0], name: row[1], price: row[2], lagerstand: row[3], mwst_satz: row[4], checkbox: checkbox, quantity: quantity_entry }
  end

  dialog_content_area.add(Gtk::Label.new("Produkte auswählen:"))
  dialog_content_area.add(products_list)

  # Datum
  date_entry = Gtk::Entry.new
  date_entry.text = Time.now.strftime("%Y-%m-%d")
  dialog_content_area.add(Gtk::Label.new("Datum:"))
  dialog_content_area.add(date_entry)

  # Checkbox für Lagerbestand-Anpassung
  adjust_stock_checkbox = Gtk::CheckButton.new("Lagerbestand anpassen")
  adjust_stock_checkbox.active = true  # Standardmäßig aktiviert
  dialog_content_area.add(adjust_stock_checkbox)

  # Checkbox für automatisches Speichern der PDF
  save_pdf_checkbox = Gtk::CheckButton.new("PDF-Rechnung automatisch speichern")
  save_pdf_checkbox.active = true  # Standardmäßig aktiviert
  dialog_content_area.add(save_pdf_checkbox)

  dialog_content_area.show_all

  response = dialog.run
  if response == :ok
    customer_id = customer_combo.active_id.to_i
    selected_products = products.select { |product| product[:checkbox].active? }

    if selected_products.empty?
      puts "Keine Produkte ausgewählt"
    else
      total_sum = 0
      total_mwst = 0
      selected_products.each do |product|
        quantity = product[:quantity].text.to_i
        price_with_vat = product[:price]
        mwst_satz = product[:mwst_satz] || 20.0
        price_without_vat = price_with_vat / (1 + mwst_satz / 100.0)
        product_total = price_without_vat * quantity
        product_mwst = product_total * (mwst_satz / 100.0)
        total_sum += product_total
        total_mwst += product_mwst
      end

      date = date_entry.text
      DATABASE.execute("INSERT INTO rechnungen (kunde, summe, datum, bezahlt) VALUES (?, ?, ?, ?)", [customer_id, total_sum + total_mwst, date, 0])
      invoice_id = DATABASE.last_insert_row_id

      # Speichern der Rechnungspositionen
      selected_products.each do |product|
        quantity = product[:quantity].text.to_i
        price_with_vat = product[:price]
        mwst_satz = product[:mwst_satz] || 20.0
        price_without_vat = (price_with_vat / (1 + mwst_satz / 100.0)).round(2)

        gesamtpreis_netto = (price_without_vat * quantity).round(2)
        mwst_betrag = (gesamtpreis_netto * (mwst_satz / 100.0)).round(2)
        gesamtpreis_brutto = (gesamtpreis_netto + mwst_betrag).round(2)

        DATABASE.execute("INSERT INTO rechnungspositionen (rechnung_id, produkt_id, menge, einzelpreis_netto, mwst_satz, einzelpreis_brutto, gesamtpreis_netto, gesamtpreis_brutto, mwst_betrag) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         [invoice_id, product[:id], quantity, price_without_vat, mwst_satz, price_with_vat, gesamtpreis_netto, gesamtpreis_brutto, mwst_betrag])
      end

      if adjust_stock_checkbox.active?
        adjust_stock(selected_products)
      end

      load_rechnungen_to_list_store(@list_store)
      puts "Rechnung erstellt"

      if save_pdf_checkbox.active?
        generate_pdf(invoice_id, customer_id, selected_products, total_sum, total_mwst, date)
      end
    end
  end

  dialog.destroy
end

def generate_pdf(invoice_id, customer_id, selected_products, total_sum, total_mwst, date)
  customer_data = DATABASE.execute('SELECT name, strasse, hausnummer, plz, stadt, email, telefon FROM kunden WHERE id = ?', customer_id).first

  # Prüfe, ob bereits eine Rechnungsnummer existiert
  existing_invoice_number = DATABASE.execute("SELECT invoice_number FROM rechnungen WHERE id = ?", invoice_id).first

  if existing_invoice_number && existing_invoice_number[0]
    invoice_number = existing_invoice_number[0]
  else
    # Generiere die Rechnungsnummer basierend auf dem Jahr und der letzten Nummer
    year = Date.parse(date).year
    last_invoice_number = DATABASE.execute("SELECT MAX(CAST(SUBSTR(invoice_number, 5) AS INTEGER)) FROM rechnungen WHERE strftime('%Y', datum) = ?", year.to_s).first[0] || 0
    next_number = (last_invoice_number + 1).to_s.rjust(5, '0')
    invoice_number = "#{year}#{next_number}"

    # Speichere die neue Rechnungsnummer in der Datenbank
    DATABASE.execute("UPDATE rechnungen SET invoice_number = ? WHERE id = ?", [invoice_number, invoice_id])
  end

  Prawn::Document.generate("Rechnung_#{invoice_number}.pdf") do |pdf|
    pdf.font "Helvetica"

    # Fügen Sie hier Ihre Firmeninformationen hinzu
    pdf.text "Ihre Firma", size: 20, style: :bold
    pdf.text "Firmenstraße 123"
    pdf.text "12345 Firmenstadt"
    pdf.move_down 20

    # Kundenadresse
    pdf.text "Rechnung an:", style: :bold
    pdf.text customer_data[0]
    pdf.text "#{customer_data[1]} #{customer_data[2]}"
    pdf.text "#{customer_data[3]} #{customer_data[4]}"
    pdf.move_down 10
    pdf.text "E-Mail: #{customer_data[5]}" if customer_data[5]
    pdf.text "Telefon: #{customer_data[6]}" if customer_data[6]

    pdf.move_down 20

    pdf.text "Rechnung Nr. #{invoice_number}", size: 16, style: :bold
    pdf.text "Datum: #{date}"
    pdf.move_down 20

    # Hole die gespeicherten Rechnungspositionen
    items = [["Produkt", "Menge", "Einzelpreis (netto)", "MwSt-Satz", "MwSt", "Gesamt"]]
    total = 0
    total_sum = 0
    total_mwst = 0

    DATABASE.execute('SELECT p.name, rp.menge, rp.einzelpreis_netto, rp.mwst_satz, rp.mwst_betrag, rp.gesamtpreis_brutto FROM rechnungspositionen rp JOIN produkte p ON rp.produkt_id = p.id WHERE rp.rechnung_id = ?', invoice_id) do |row|
      name, quantity, price_without_vat, mwst_satz, mwst, subtotal = row

      items << [
        name,
        quantity,
        sprintf("%.2f €", price_without_vat),
        "#{mwst_satz}%",
        sprintf("%.2f €", mwst),
        sprintf("%.2f €", subtotal)
      ]

      total += subtotal
      total_sum += (subtotal - mwst)
      total_mwst += mwst
    end

    pdf.table(items, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      columns(2..5).align = :right
    end

    pdf.move_down 10
    pdf.text "Nettobetrag: #{sprintf("%.2f €", total_sum.round(2))}", align: :right
    pdf.text "MwSt: #{sprintf("%.2f €", total_mwst.round(2))}", align: :right
    pdf.text "Gesamtbetrag: #{sprintf("%.2f €", total.round(2))}", size: 16, style: :bold, align: :right

    pdf.move_down 40
    pdf.text "Vielen Dank für Ihren Einkauf!", align: :center
  end

  puts "PDF-Rechnung wurde erstellt: Rechnung_#{invoice_number}.pdf"
end

def load_rechnungen_to_list_store(list_store)
  # Check if list_store is nil
  if list_store.nil?
    puts "Error: list_store is nil"
    return
  end

  list_store.clear

  DATABASE.execute('SELECT rechnungen.id, kunden.name, rechnungen.summe, rechnungen.datum, rechnungen.bezahlt FROM rechnungen JOIN kunden ON rechnungen.kunde = kunden.id') do |row|
    # Konvertieren Sie die Werte in die erwarteten Typen
    id = row[0].to_i
    name = row[1].to_s
    summe = row[2].to_f
    datum = row[3].to_s
    bezahlt = row[4].to_i

    # Fügen Sie die Werte zum ListStore hinzu
    iter = list_store.append
    iter[0] = id
    iter[1] = name
    iter[2] = summe
    iter[3] = datum
    iter[4] = bezahlt
  end
end
end

app = RechnungApp.new
Gtk.main
