require 'gtk3'
require 'prawn'
require 'prawn/table'
require 'mysql2'
require 'yaml'
require 'rqrcode'
require 'base64'
#require 'date'


class InvoiceManager

  def initialize
    @config_file = 'config.yml'


    @window = Gtk::Window.new("Rechnungsverwaltung")
    @window.set_default_size(800, 600)
    #@window.set_border_width(5)
    @window.signal_connect("destroy") { Gtk.main_quit }

    check_and_load_config
  end

  def check_and_load_config
    config = load_config
    if config_valid?(config)
      if test_db_connection == false
        setup_ui(false)
      else
        setup_ui(true)
        create_tables
      end
    else
      create_config_window(true)
    end
  end

  def config_valid?(config)
    db_config = config['db']
    return false if db_config.nil?
    ['host', 'username', 'password', 'database'].all? { |key| db_config[key] && !db_config[key].empty? }
  end

  def setup_ui(db_ok)
    vbox = Gtk::Box.new(:vertical, 5)
    @window.add(vbox)

    # Menüleiste
    menubar = Gtk::MenuBar.new
    vbox.pack_start(menubar, expand: false, fill: false, padding: 0)

    # Datei Menü
    file_menu = Gtk::Menu.new
    file_item = Gtk::MenuItem.new(label: "Datei")
    file_item.set_submenu(file_menu)

    # Punkt für Konfig Bearbeiten
    edit_config_item = Gtk::MenuItem.new(label: "Konfiguration bearbeiten")
    edit_config_item.signal_connect("activate") { create_config_window }
    file_menu.append(edit_config_item)

    # Punkt für DB Verbindung testeb
    test_db_item = Gtk::MenuItem.new(label: "Teste DB Verbindung")
    test_db_item.signal_connect("activate") { test_db_connection }
    file_menu.append(test_db_item)


    # Punkt für das Beenden des Programms
    exit_item = Gtk::MenuItem.new(label: "Beenden")
    exit_item.signal_connect("activate") { Gtk.main_quit }
    file_menu.append(exit_item)

    menubar.append(file_item)

    # Info-Menü
    info_menu = Gtk::Menu.new
    info_item = Gtk::MenuItem.new(label: "Info")
    info_item.set_submenu(info_menu)

    add_info_item = Gtk::MenuItem.new(label: "Info anzeigen")
    add_info_item.signal_connect("activate") { show_info_dialog("INFO") }
    info_menu.append(add_info_item)

    menubar.append(info_item)

    # Hauptbereich
    
    # Notebook erstellen
    @notebook = Gtk::Notebook.new
    vbox.pack_start(@notebook, expand: true, fill: true, padding: 0)

    # IF DB Connection not OK do not load the tabs
    if db_ok == true
      # Seiten zum Notebook hinzufügen
      # Erstelle die Tabs mit unterschiedlichen TreeViews
      # Definiere Tabellen und entsprechende Labels für die Tabs
      tabs = {
        "Rechnungen" => "t_invoices",
        "Kunden" => "t_customers",
        "Produkte" => "t_products",
      }

      # Erstelle die Tabs dynamisch
      tabs.each do |tab_label, table_name|
        create_tab(tab_label, table_name)
      end
    end

    # Statusleiste erstellen
    @statusbar = Gtk::Statusbar.new
    # Statusleiste anzeigen/hinzufügen
    vbox.pack_start(@statusbar, expand: false, fill: false, padding: 0)

    @window.show_all
  end

  def show_info_dialog(message)
    dialog = Gtk::MessageDialog.new(
      parent: @window,
      flags: :destroy_with_parent,
      type: :info,
      buttons: :OK,
      message: message
    )
    dialog.run
    dialog.destroy
  end

  # Methode zum Speichern der Konfiguration
  def save_config(host, username, password, database, logo_path, pdf_path, comapany_name, company_street, company_city, company_iban, company_bic)
    config = {
      'db' => {
        'host' => host,
        'username' => username,
        'password' => password,
        'database' => database
      },
      'logo' => logo_path,
      'pdf_path' => pdf_path,
      'company' => {
        'name' => comapany_name,
        'street' => company_street,
        'city' => company_city,
        'iban' => company_iban,
        'bic' => company_bic
        
      }
    }

    File.open(@config_file, 'w') do |file|
      file.write(config.to_yaml)
    end
  end

  # Methode zum Laden der Konfiguration
  def load_config
    default_config = {
      'db' => {
        'host' => '',
        'username' => '',
        'password' => '',
        'database' => ''
      },
      'logo' => '',
      'pdf_path' => '',
    }
    if File.exist?(@config_file)
      loaded_config = YAML.load_file(@config_file) || {}
      default_config.merge(loaded_config) do |key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          old_val.merge(new_val)
        else
          new_val
        end
      end
    else
      puts "ERROR: Keine Konfiguratisdatei gefunden!"
      default_config
    end
  end

  # Methode zum Erstellen des Konfigurationsfensters
  def create_config_window(initial_setup = false)
    config = load_config
    db_config = config['db'] || {}
    company_config = config['company'] || {}

    config_window = Gtk::Window.new('DB Config')
    config_window.set_size_request(400, 250)
    config_window.set_border_width(10)

    grid = Gtk::Grid.new
    grid.row_spacing = 10
    grid.column_spacing = 10

    host_label = Gtk::Label.new('Host:')
    username_label = Gtk::Label.new('Username:')
    password_label = Gtk::Label.new('Password:')
    database_label = Gtk::Label.new('Database:')
    logo_label = Gtk::Label.new('Logo:')
    pdf_label = Gtk::Label.new('PDF Path:')
    company_name_label = Gtk::Label.new('My company:')
    company_street_label = Gtk::Label.new('My street:')
    company_city_label = Gtk::Label.new('My city:')
    company_iban_label = Gtk::Label.new('IBAN:')
    company_bic_label = Gtk::Label.new('BIC:')

    host_entry = Gtk::Entry.new
    username_entry = Gtk::Entry.new
    password_entry = Gtk::Entry.new
    database_entry = Gtk::Entry.new
    logo_entry = Gtk::Entry.new
    pdf_entry = Gtk::Entry.new
    company_name_entry = Gtk::Entry.new
    company_street_entry = Gtk::Entry.new
    company_city_entry = Gtk::Entry.new
    company_iban_entry = Gtk::Entry.new
    company_bic_entry = Gtk::Entry.new

    host_entry.text = db_config['host'] || ''
    username_entry.text = db_config['username'] || ''
    password_entry.text = db_config['password'] || ''
    database_entry.text = db_config['database'] || ''
    logo_entry.text = config['logo'] || ''
    pdf_entry.text = config['pdf_path'] || ''
    company_name_entry.text = company_config['name'] || ''
    company_street_entry.text = company_config['street'] || ''
    company_city_entry.text = company_config['city'] || ''
    company_iban_entry.text = company_config['iban'] || ''
    company_bic_entry.text = company_config['bic'] || ''

    logo_button = Gtk::Button.new(label: 'Browse...')
    logo_button.signal_connect('clicked') do
      dialog = Gtk::FileChooserDialog.new(
        title: "Select Logo",
        parent: config_window,
        action: :open,
        buttons: [
          ['Cancel', :cancel],
          ['Open', :accept]
        ]
      )
      filter = Gtk::FileFilter.new
      filter.name = "Image Files"
      filter.add_mime_type("image/png")
      filter.add_mime_type("image/jpeg")
      dialog.add_filter(filter)

      if dialog.run == :accept
        logo_entry.text = dialog.filename
      end

      dialog.destroy
    end

    pdf_button = Gtk::Button.new(label: 'Browse...')
    pdf_button.signal_connect('clicked') do
      dialog = Gtk::FileChooserDialog.new(
        title: "Select PDF Save Directory",
        parent: config_window,
        action: :select_folder,
        buttons: [
          ['Cancel', :cancel],
          ['Select', :accept]
        ]
      )

      if dialog.run == :accept
        pdf_entry.text = dialog.filename
      end

      dialog.destroy
    end

    save_button = Gtk::Button.new(label: 'Save')
    save_button.signal_connect('clicked') do
      save_config(host_entry.text,
                  username_entry.text,
                  password_entry.text,
                  database_entry.text,
                  logo_entry.text,
                  pdf_entry.text,
                  company_name_entry.text,
                  company_street_entry.text,
                  company_city_entry.text,
                  company_iban_entry.text,
                  company_bic_entry.text)
      config = load_config
      if config_valid?(config)
        @statusbar.push(0, 'Configuration saved successfully!')
        config_window.destroy
        if initial_setup
          setup_ui
          create_tables
        end
      else
        @statusbar.push(0, 'Invalid configuration. Please fill all required fields.')
      end
    end

    grid.attach(host_label, 0, 0, 1, 1)
    grid.attach(host_entry, 1, 0, 2, 1)
    grid.attach(username_label, 0, 1, 1, 1)
    grid.attach(username_entry, 1, 1, 2, 1)
    grid.attach(password_label, 0, 2, 1, 1)
    grid.attach(password_entry, 1, 2, 2, 1)
    grid.attach(database_label, 0, 3, 1, 1)
    grid.attach(database_entry, 1, 3, 2, 1)
    grid.attach(logo_label, 0, 4, 1, 1)
    grid.attach(logo_entry, 1, 4, 1, 1)
    grid.attach(logo_button, 2, 4, 1, 1)
    grid.attach(pdf_label, 0, 5, 1, 1)
    grid.attach(pdf_entry, 1, 5, 1, 1)
    grid.attach(pdf_button, 2, 5, 1, 1)
    ###
    grid.attach(company_name_label, 0, 6, 1, 1)
    grid.attach(company_name_entry, 1, 6, 2, 1)
    grid.attach(company_street_label, 0, 7, 1, 1)
    grid.attach(company_street_entry, 1, 7, 2, 1)
    grid.attach(company_city_label, 0, 8, 1, 1)
    grid.attach(company_city_entry, 1, 8, 2, 1)
    grid.attach(company_iban_label, 0, 9, 1, 1)
    grid.attach(company_iban_entry, 1, 9, 2, 1)
    grid.attach(company_bic_label, 0, 10, 1, 1)
    grid.attach(company_bic_entry, 1, 10, 2, 1)
    ###
    grid.attach(save_button, 0, 11, 3, 1)

    # Verhindere, dass das Konfigurationsfenster geschlossen werden kann, wenn es die initiale Einrichtung ist
    if initial_setup
      config_window.signal_connect('delete-event') { |_, _| true }
    end

    config_window.add(grid)
    config_window.set_transient_for(@window)
    config_window.show_all
  end

  # Methode zum Anzeigen der Konfiguration - bur zum testen
  def show_config
    config = load_config
    db_config = config['db']
    logo_path = config['logo']

    message = "DB Configuration:\n" +
      "Host: #{db_config['host']}\n" +
      "Username: #{db_config['username']}\n" +
      "Password: #{db_config['password']}\n" +
      "Database: #{db_config['database']}\n" +
      "Logo Path: #{logo_path}"

    dialog = Gtk::MessageDialog.new(
      parent: @window,
      flags: :modal,
      type: :info,
      buttons_type: :ok,
      message: message
    )
    dialog.run
    dialog.destroy
  end

  def test_db_connection
    config = load_config
    db_config = config['db']

    begin
      # Konfiguriere deine Datenbankverbindungsdetails
      client = Mysql2::Client.new(
        host: db_config['host'],
        username: db_config['username'],
        password: db_config['password'],
        database: db_config['database']
      )

      # Teste die Verbindung
      results = client.query("SELECT VERSION()")
      version = results.first['VERSION()']
      if defined?(@statusbar)
        @statusbar.push(@statusbar.get_context_id('info'), "Erfolgreich verbunden - DB-Version: #{version}")
      end
    rescue Mysql2::Error => e
      puts "Verbindung zu DB fehlgeschlagen! - #{e.message}"
      if defined?(@statusbar)
        @statusbar.push(@statusbar.get_context_id('error'), "ERROR - Datenbank nicht erreichbar.")
      end
      return false
    ensure
      client.close if client
    end
  end

  def create_tables
    config = load_config
    db_config = config['db']

    # Konfiguriere deine Datenbankverbindungsdetails
    client = Mysql2::Client.new(
      host: db_config['host'],
      username: db_config['username'],
      password: db_config['password'],
      database: db_config['database']
    )

    # Tabellen erstellen
    create_table_customers = <<-SQL
      CREATE TABLE IF NOT EXISTS t_customers (
      customer_id INT AUTO_INCREMENT PRIMARY KEY,
      name TEXT NOT NULL,
      street TEXT,
      housenumber TEXT,
      zip TEXT,
      city TEXT,
      email TEXT,
      phone TEXT);
    SQL

    create_table_invoices = <<-SQL
      CREATE TABLE IF NOT EXISTS t_invoices (
      invoice_id INT AUTO_INCREMENT PRIMARY KEY,
      invoice_number VARCHAR(100) NOT NULL,
      sum DECIMAL(10, 2),
      paid BOOLEAN DEFAULT FALSE,
      customer_id INT,
          FOREIGN KEY (customer_id) REFERENCES t_customers(customer_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE);
    SQL


    create_table_products = <<-SQL
      CREATE TABLE IF NOT EXISTS t_products (
      product_id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      tax DECIMAL(5, 2),
      brutto DECIMAL(10, 2),
      stored INT,
      tosell BOOLEAN DEFAULT TRUE);
    SQL

    create_table_billed_products = <<-SQL
        CREATE TABLE IF NOT EXISTS t_billed_products (
        invoice_id INT, 
        product_count INT, 
        product_id INT, 
        FOREIGN KEY (invoice_id) 
        REFERENCES t_invoices(invoice_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE);
    SQL


    begin
      client.query(create_table_invoices)
      client.query(create_table_customers)
      client.query(create_table_products)
      client.query(create_table_billed_products)
    rescue Mysql2::Error => e
      puts "Tabellen erstellen fehlgeschlagen! - #{e.message}"
      @statusbar.push(@statusbar.get_context_id('error'), "ERROR: Tabellen erstellen fehlgeschlagen!")
    ensure
      client.close if client
    end
  end

  def create_tab(tab_label, table_name)
    # Erstelle eine vertikale Box
    vbox = Gtk::Box.new(:vertical, 5)

    # Erstelle ein Suchfeld und einen Suchbutton
    search_box = Gtk::Box.new(:horizontal, 5)
    search_entry = Gtk::Entry.new
    search_entry.set_placeholder_text("Suche...")
    search_button = Gtk::Button.new(label: "Suchen")
    search_box.pack_start(search_entry, expand: true, fill: true, padding: 5)
    search_box.pack_start(search_button, expand: false, fill: false, padding: 5)
    vbox.pack_start(search_box, expand: false, fill: false, padding: 5)

    # Erstelle ein TreeView und ein ScrolledWindow für den Tab
    treeview = Gtk::TreeView.new
    scrolled_window = Gtk::ScrolledWindow.new
    scrolled_window.set_policy(:automatic, :automatic)
    scrolled_window.add(treeview)
    vbox.pack_start(scrolled_window, expand: true, fill: true, padding: 5)

    # Lade die Daten aus der angegebenen Tabelle und füge sie zum TreeView hinzu
    load_data_from_db(treeview, table_name)

    # Erstelle eine horizontale Box für die Buttons
    hbox = Gtk::Box.new(:horizontal, 5)

    # Erstelle Buttons
    new_button = Gtk::Button.new(label: "Neu Erstellen")
    edit_button = Gtk::Button.new(label: "Bearbeiten")
    delete_button = Gtk::Button.new(label: "Löschen")
    hbox.pack_start(new_button, expand: true, fill: true, padding: 5)
    hbox.pack_start(edit_button, expand: true, fill: true, padding: 5)
    hbox.pack_start(delete_button, expand: true, fill: true, padding: 5)

    # Füge die horizontale Box zur vertikalen Box hinzu
    vbox.pack_start(hbox, expand: false, fill: false, padding: 5)

    # Füge den Tab mit dem VBox zum Notebook hinzu
    @notebook.append_page(vbox, Gtk::Label.new(tab_label))

    # Verbinde die Suchfunktion mit dem Button und der Enter-Taste
    search_button.signal_connect("clicked") do
      filter_treeview(treeview, search_entry.text)
    end

    search_entry.signal_connect("activate") do
      filter_treeview(treeview, search_entry.text)
    end
    # Verbinde die Buttons mit entsprechenden Aktionen (Platzhalter-Funktionen)
    new_button.signal_connect("clicked") { on_new_button_clicked(table_name) }
    edit_button.signal_connect("clicked") { on_edit_button_clicked(treeview, table_name) }
    delete_button.signal_connect("clicked") { on_delete_button_clicked(treeview, table_name) }
  end

  def load_data_from_db(treeview, table_name)
    config = load_config
    db_config = config['db']

    begin
      # Konfiguriere die Datenbankverbindung
      client = Mysql2::Client.new(
        host: db_config['host'],
        username: db_config['username'],
        password: db_config['password'],
        database: db_config['database']
      )

      # Je nach Tabelle eine entsprechen Query bauen
      case table_name
      when "t_customers"
        myQuery = "SELECT customer_id AS 'Kunden-NR.', name AS 'Kunde', phone AS 'Telefon-Nr.', email as 'E-Mail' FROM #{table_name}"
      when "t_products"
        myQuery = "SELECT product_id AS 'Produkt-NR.', name AS 'Produkt', brutto AS 'Preis', stored AS 'Auf Lager', tax AS 'MWSt in %' FROM #{table_name}"
      when "t_invoices"
        myQuery = "SELECT invoice_number AS 'Rechnungs-NR', sum AS 'Summe', t_customers.name as 'Name', paid AS 'Bezahlt' FROM #{table_name}
                  JOIN t_customers ON #{table_name}.customer_id = t_customers.customer_id ORDER BY invoice_number DESC"
      end

      # Abfrage ausführen
      results = client.query(myQuery)

      # Erstelle die Spalten für das TreeView
      create_columns(treeview, results.fields)

      # Erstelle das ListStore-Modell für das TreeView
      list_store = Gtk::ListStore.new(*Array.new(results.fields.size, String))

      # Lade die Daten in das ListStore
      results.each do |row|
        iter = list_store.append
        row.values.each_with_index do |value, index|
          iter[index] = value.to_s
        end
      end

      # Setze das Modell für das TreeView
      treeview.model = list_store

    rescue Mysql2::Error => e
      puts "Fehler beim Verbinden zur Datenbank: #{e.message}"
    ensure
      client.close if client
    end
  end

def create_columns(treeview, column_names)
  column_names.each_with_index do |col_name, index|
    renderer = Gtk::CellRendererText.new
    column = Gtk::TreeViewColumn.new(col_name, renderer, text: index)
    column.resizable = true
    column.set_cell_data_func(renderer) do |column, cell, model, iter|
      value = iter[index]
      if ['Preis', 'MWSt in %', 'Summe'].include?(col_name)
        cell.text = sprintf("%.2f", value.to_f)
      elsif col_name == 'Bezahlt'
        cell.text = value == '1' ? 'Ja' : 'Nein'
      else
        cell.text = value.to_s
      end
    end
    treeview.append_column(column)
  end
end

  def filter_treeview(treeview, query)
    original_model = treeview.model.is_a?(Gtk::TreeModelFilter) ? treeview.model.model : treeview.model

    if query.strip.empty?
      treeview.model = original_model  # Reset to the original model if query is empty
    else
      filtered_model = Gtk::TreeModelFilter.new(original_model)
      filtered_model.set_visible_func do |model, iter|
        model.n_columns.times.any? do |i|
          value = model.get_value(iter, i).to_s.downcase
          query.downcase.split.all? { |word| value.include?(word) }
        end
      end
      treeview.model = filtered_model
    end
  end

  def on_new_button_clicked(table_name)
    # Je nach Tabelle eine entsprechen ADD Funktion aufrufen.
    case table_name
    when "t_customers"
      @statusbar.push(@statusbar.get_context_id('info'), "Neuen Kunden hinzufügen")
      create_customer_window
    when "t_products"
      @statusbar.push(@statusbar.get_context_id('info'), "Neues Produkt hinzufügen")
      add_product_window
    when "t_invoices"
      create_invoice_window
      @statusbar.push(@statusbar.get_context_id('info'), "Neue Rechnung erstellen")
    end
  end

  def on_delete_button_clicked(treeview, table_name)
    selection = treeview.selection
    if (iter = selection.selected)
      id = iter[0]
      confirm_dialog = Gtk::MessageDialog.new(
        parent: @window,
        flags: :destroy_with_parent,
        type: :question,
        buttons: :yes_no,
        message: "Sind Sie sicher, dass Sie diesen Eintrag löschen möchten?"
      )
      response = confirm_dialog.run
      confirm_dialog.destroy

      if response == Gtk::ResponseType::YES
        delete_from_db(table_name, id)
        refresh_current_tab
      end
    else
      puts "Kein Eintrag ausgewählt zum Löschen."
      @statusbar.push(@statusbar.get_context_id('warning'), "Kein Eintrag ausgewählt zum Löschen.")
    end
  end

  def delete_from_db(table_name, id)
    config = load_config
    db_config = config['db']

    begin
      client = Mysql2::Client.new(
        host: db_config['host'],
        username: db_config['username'],
        password: db_config['password'],
        database: db_config['database']
      )

      case table_name
      when "t_customers"
        myQuery = "DELETE FROM #{table_name} WHERE customer_id = ?"
      when "t_products"
        myQuery = "DELETE FROM #{table_name} WHERE product_id = ?"
      when "t_invoices"
        myQuery = "DELETE FROM #{table_name} WHERE invoice_number = ?"
      else
        raise "Unknown table: #{table_name}"
      end

      stmt = client.prepare(myQuery)
      stmt.execute(id)

      @statusbar.push(@statusbar.get_context_id('info'), "#{id} gelöscht")

    rescue Mysql2::Error => e
      puts "Fehler beim Löschen aus der Datenbank: #{e.message}"
      @statusbar.push(@statusbar.get_context_id('error'), "Fehler beim Löschen: #{e.message}")
    ensure
      client.close if client
    end
  end

  def refresh_current_tab
    current_page = @notebook.page
    tab_child = @notebook.get_nth_page(current_page)
    treeview = tab_child.children.find { |child| child.is_a?(Gtk::ScrolledWindow) }.children.first
    table_name = case @notebook.get_tab_label_text(tab_child)
                 when "Rechnungen"
                   "t_invoices"
                 when "Kunden"
                   "t_customers"
                 when "Produkte"
                   "t_products"
                 end

    # Clear existing columns
    treeview.columns.each { |col| treeview.remove_column(col) }

    # Clear existing model
    treeview.model = nil

    # Reload data from database
    load_data_from_db(treeview, table_name)
  end

  # Methode zum Erstellen des Kundenfensters
  def create_customer_window
    customer_window = Gtk::Window.new('Kundendaten')
    customer_window.set_size_request(400, 300)
    customer_window.set_border_width(10)

    grid = Gtk::Grid.new
    grid.row_spacing = 10
    grid.column_spacing = 10

    name_label = Gtk::Label.new('Name:')
    street_label = Gtk::Label.new('Straße:')
    housenumber_label = Gtk::Label.new('Hausnummer:')
    zip_label = Gtk::Label.new('PLZ:')
    city_label = Gtk::Label.new('Stadt:')
    email_label = Gtk::Label.new('Email:')
    phone_label = Gtk::Label.new('Telefon:')

    name_entry = Gtk::Entry.new
    street_entry = Gtk::Entry.new
    housenumber_entry = Gtk::Entry.new
    zip_entry = Gtk::Entry.new
    city_entry = Gtk::Entry.new
    email_entry = Gtk::Entry.new
    phone_entry = Gtk::Entry.new

    # Setze die Mindestbreite der Eingabefelder
    name_entry.set_width_request(300)
    street_entry.set_width_request(300)
    housenumber_entry.set_width_request(300)
    zip_entry.set_width_request(300)
    city_entry.set_width_request(300)
    email_entry.set_width_request(300)
    phone_entry.set_width_request(300)

    save_button = Gtk::Button.new(label: 'Save')
    save_button.signal_connect('clicked') do
      customer_data = {
        name: name_entry.text,
        street: street_entry.text,
        housenumber: housenumber_entry.text,
        zip: zip_entry.text,
        city: city_entry.text,
        email: email_entry.text,
        phone: phone_entry.text
      }

      # Validierung: Name darf nicht leer sein
      if customer_data[:name].strip.empty?
        @statusbar.push(@statusbar.get_context_id('error'), "ERROR: Name darf nicht leer sein")
      else
        write2db("t_customers", customer_data)
        customer_window.destroy
      end
    end

    grid.attach(name_label, 0, 0, 1, 1)
    grid.attach(name_entry, 1, 0, 2, 1)
    grid.attach(street_label, 0, 1, 1, 1)
    grid.attach(street_entry, 1, 1, 2, 1)
    grid.attach(housenumber_label, 0, 2, 1, 1)
    grid.attach(housenumber_entry, 1, 2, 2, 1)
    grid.attach(zip_label, 0, 3, 1, 1)
    grid.attach(zip_entry, 1, 3, 2, 1)
    grid.attach(city_label, 0, 4, 1, 1)
    grid.attach(city_entry, 1, 4, 2, 1)
    grid.attach(email_label, 0, 5, 1, 1)
    grid.attach(email_entry, 1, 5, 2, 1)
    grid.attach(phone_label, 0, 6, 1, 1)
    grid.attach(phone_entry, 1, 6, 2, 1)
    grid.attach(save_button, 0, 7, 3, 1)

    customer_window.add(grid)
    customer_window.set_transient_for(@window)
    customer_window.show_all
  end

  def add_product_window
    dialog = Gtk::Dialog.new(
      title: "Produkt hinzufügen",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [['Abbrechen', :cancel], ['Hinzufügen', :ok]]
    )

    grid = Gtk::Grid.new
    grid.row_spacing = 5
    grid.column_spacing = 5

    name_entry = Gtk::Entry.new
    price_entry = Gtk::Entry.new
    stock_entry = Gtk::Entry.new
    vat_entry = Gtk::Entry.new
    tosell_check = Gtk::CheckButton.new("Zum Verkauf")
    tosell_check.active = true  # Pre-checked

    name_entry.set_width_request(300)

    grid.attach(Gtk::Label.new("Name:"), 0, 0, 1, 1)
    grid.attach(name_entry, 1, 0, 1, 1)
    grid.attach(Gtk::Label.new("Preis:"), 0, 1, 1, 1)
    grid.attach(price_entry, 1, 1, 1, 1)
    grid.attach(Gtk::Label.new("Lagerbestand:"), 0, 2, 1, 1)
    grid.attach(stock_entry, 1, 2, 1, 1)
    grid.attach(Gtk::Label.new("MwSt-Satz:"), 0, 3, 1, 1)
    grid.attach(vat_entry, 1, 3, 1, 1)
    grid.attach(tosell_check, 0, 4, 2, 1)

    dialog.content_area.add(grid)
    dialog.show_all

    response = dialog.run
    if response == :ok
      product_data = {
        name: name_entry.text,
        price: price_entry.text.gsub(',', '.').to_f,
        stock: stock_entry.text.to_i,
        vat: vat_entry.text.gsub(',', '.').to_f,
        tosell: tosell_check.active? ? 1 : 0
      }

      write2db("t_products", product_data)
      refresh_current_tab
    end

    dialog.destroy
  end

  def on_edit_button_clicked(treeview, table_name)
    selection = treeview.selection
    if (iter = selection.selected)
      case table_name
      when "t_customers"
        customer_id = iter[0]
        edit_customer_window(customer_id)
      when "t_products"
        product_id = iter[0]
        edit_product_window(product_id)
      when "t_invoices"
        invoice_number = iter[0]
        edit_invoice_window(invoice_number)
      end
    else
      puts "Kein Eintrag ausgewählt zum Bearbeiten."
    end
  end

  def edit_customer_window(customer_id)
    customer_window = Gtk::Window.new('Kundendaten bearbeiten')
    customer_window.set_size_request(400, 300)
    customer_window.set_border_width(10)

    grid = Gtk::Grid.new
    grid.row_spacing = 10
    grid.column_spacing = 10

    # Create labels and entry fields
    fields = %w(name street housenumber zip city email phone)
    labels = {}
    entries = {}

    fields.each_with_index do |field, index|
      labels[field] = Gtk::Label.new("#{field.capitalize}:")
      entries[field] = Gtk::Entry.new
      entries[field].set_width_request(300)
      grid.attach(labels[field], 0, index, 1, 1)
      grid.attach(entries[field], 1, index, 2, 1)
    end

    # Fetch customer data from database
    config = load_config
    db_config = config['db']
    client = Mysql2::Client.new(host: db_config['host'], username: db_config['username'], password: db_config['password'], database: db_config['database'])
    result = client.query("SELECT * FROM t_customers WHERE customer_id = #{customer_id}").first

    # Populate entry fields with current data
    fields.each do |field|
      entries[field].text = result[field].to_s
    end

    save_button = Gtk::Button.new(label: 'Speichern')
    save_button.signal_connect('clicked') do
      updated_data = fields.map { |field| [field.to_sym, entries[field].text] }.to_h
      write2db("t_customers", updated_data, customer_id)
      customer_window.destroy
      refresh_current_tab
    end

    grid.attach(save_button, 0, fields.length, 3, 1)

    customer_window.add(grid)
    customer_window.set_transient_for(@window)
    customer_window.show_all

    client.close
  end

  def edit_product_window(product_id)
    product_window = Gtk::Window.new('Produkt bearbeiten')
    product_window.set_size_request(400, 300)
    product_window.set_border_width(10)

    grid = Gtk::Grid.new
    grid.row_spacing = 10
    grid.column_spacing = 10

    fields = %w(name brutto stored tax tosell)
    labels = {}
    entries = {}

    fields.each_with_index do |field, index|
      labels[field] = Gtk::Label.new("#{field.capitalize}:")
      entries[field] = Gtk::Entry.new
      entries[field].set_width_request(300)
      grid.attach(labels[field], 0, index, 1, 1)
      grid.attach(entries[field], 1, index, 2, 1)
    end

    # Replace 'tosell' Entry with CheckButton
    grid.remove(entries['tosell'])
    entries['tosell'] = Gtk::CheckButton.new("Zum Verkauf")
    grid.attach(entries['tosell'], 1, 4, 2, 1)

    # Fetch product data from database
    config = load_config
    db_config = config['db']
    client = Mysql2::Client.new(host: db_config['host'], username: db_config['username'], password: db_config['password'], database: db_config['database'])
    result = client.query("SELECT * FROM t_products WHERE product_id = #{product_id}").first

    # Populate entry fields with current data
    fields.each do |field|
      case field
      when 'tosell'
        entries[field].active = result[field] == 1
      when 'brutto', 'tax'
        entries[field].text = sprintf('%.2f', result[field])
      when 'stored'
        entries[field].text = result[field].to_i.to_s
      else
        entries[field].text = result[field].to_s
      end
    end

    save_button = Gtk::Button.new(label: 'Speichern')
    save_button.signal_connect('clicked') do
      updated_data = {
        name: entries['name'].text,
        brutto: entries['brutto'].text.gsub(',', '.').to_f,
        stored: entries['stored'].text.to_i,
        tax: entries['tax'].text.gsub(',', '.').to_f,
        tosell: entries['tosell'].active? ? 1 : 0
      }
      write2db("t_products", updated_data, product_id)
      product_window.destroy
      refresh_current_tab
    end

    grid.attach(save_button, 0, fields.length, 3, 1)

    product_window.add(grid)
    product_window.set_transient_for(@window)
    product_window.show_all

    client.close
  end
  
  def edit_invoice_window(invoice_number)
    invoice = get_from_DB("SELECT invoice_number, paid FROM t_invoices WHERE invoice_number = #{invoice_number}", false).first

    dialog = Gtk::Dialog.new(
      title: "Rechnung bearbeiten",
      parent: @window,
      flags: :destroy_with_parent,
      buttons: [['Abbrechen', Gtk::ResponseType::CANCEL], ['Speichern', Gtk::ResponseType::ACCEPT]]
    )

    content_area = dialog.content_area

    ### TODO
    # PDF erzeugen Button hinzufügen
    #pdf_button = Gtk::Button.new(label: "PDF erzeugen")
    #pdf_button.signal_connect("clicked") do
    #  generate_pdf(invoice_number)
    #end
    #content_area.add(pdf_button)
    
    paid_checkbox = Gtk::CheckButton.new("Bezahlt")
    paid_checkbox.active = (invoice['paid'] == 1)
    content_area.add(paid_checkbox)
    content_area.show_all
  
    response = dialog.run
    if response == Gtk::ResponseType::ACCEPT
      #new_paid_status = paid_checkbox.active? ? 1 : 0
      updated_data = {
        #paid: new_paid_status
        paid: paid_checkbox.active? ? 1 : 0
        }

      write2db("t_invoices", updated_data, invoice_number)

      refresh_current_tab
    end

    dialog.destroy
  end

  def get_from_DB(my_query, as_array)
    config = load_config
    db_config = config['db']
    begin
      # Konfiguriere die Datenbankverbindung
      client = Mysql2::Client.new(
        host: db_config['host'],
        username: db_config['username'],
        password: db_config['password'],
        database: db_config['database']
      )

      # Abfrage ausführen
      if as_array == true
        result = client.query(my_query, as: :array)
      else
        result = client.query(my_query)
      end

      return result

    rescue Mysql2::Error => e
      puts "Fehler beim Verbinden zur Datenbank: #{e.message}"
    ensure
      client.close if client
    end
  end
  
  def get_next_invoice_number(date)
    current_year = date.split('-')[0]

    query = "SELECT MAX(invoice_number) FROM t_invoices WHERE invoice_number LIKE '#{current_year}%';"

    result = get_from_DB(query, true).first

    if result[0].to_i == 0
      invoice_number = "#{current_year}00001"
    else
      invoice_number = result[0].to_i + 1
    end
    return invoice_number
  end

  def create_invoice_window
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

    get_from_DB("SELECT customer_id, name FROM t_customers ORDER BY name ASC;", true).each do |row|
      customer_combo.append(row[0].to_s, row[1])
    end
    dialog_content_area.add(Gtk::Label.new("Kunde auswählen:"))
    dialog_content_area.add(customer_combo)

    # Produkte auswählen
    scrolled_window = Gtk::ScrolledWindow.new
    scrolled_window.set_policy(:never, :automatic)
    scrolled_window.set_size_request(-1, 150) # Adjust height as needed for 5 items

    products_list = Gtk::ListBox.new
    products_list.selection_mode = :none
    products = []

    get_from_DB("SELECT product_id, name, brutto, stored, tax FROM t_products WHERE tosell = true ORDER BY product_id DESC;", true).each do |row|
      row_box = Gtk::Box.new(:horizontal, 10)
      checkbox = Gtk::CheckButton.new("#{row[1]} - #{row[2].to_f} EUR (Lager: #{row[3] || 'N/A'})")
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
      products << { id: row[0], name: row[1], price: row[2], stored: row[3], tax: row[4], checkbox: checkbox, quantity: quantity_entry }
    end

    scrolled_window.add(products_list)
    dialog_content_area.add(Gtk::Label.new("Produkte auswählen:"))
    dialog_content_area.add(scrolled_window)

    #dialog_content_area.add(Gtk::Label.new("Produkte auswählen:"))
    #dialog_content_area.add(products_list)

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
        selected_products.each do |product|
          quantity = product[:quantity].text.to_i
          price_with_vat = product[:price]
          product_total = price_with_vat * quantity
          total_sum += product_total
        end

        date = date_entry.text

        this_invoice_number = get_next_invoice_number(date)
        #puts this_invoice_number.first&.first

        invoice_data = {
          sum: total_sum,
          date: date,
          customer_id: customer_id,
          invoice_number: this_invoice_number
        }
        write2db("t_invoices", invoice_data)

        # Get the first field from the result and jsut save the value to a variable. This is the ID of the new invoice.
        this_invoice_id = get_from_DB("SELECT invoice_id FROM t_invoices WHERE invoice_number = '#{this_invoice_number}';", false).first['invoice_id']

          # Speichern der Rechnungspositionen
        billed_data = { }
        selected_products.each do |product|
          billed_data = {
            invoice_id: this_invoice_id,
            product_count: product[:quantity].text.to_i,
            product_id: product[:id]
          }

          write2db("t_billed_products", billed_data)

        end


        if adjust_stock_checkbox.active?
          adjust_stock(selected_products)
        end

        if save_pdf_checkbox.active?
          generate_pdf(this_invoice_id, customer_id, selected_products, date)
          @statusbar.push(@statusbar.get_context_id('info'), "PDF wurde erstellt.")
        end
      end
    end

    dialog.destroy
  end

  def adjust_stock(selected_products)
    selected_products.each do |product|
      if product[:lagerstand]
        new_stock = product[:lagerstand] - product[:quantity].text.to_i
        new_stock = 0 if new_stock < 0
        write2db("t_products", { stored: new_stock }, product[:id])
      end
    end
  end

  def write2db(table_name, values, id = nil)
    config = load_config
    db_config = config['db']

    begin
      client = Mysql2::Client.new(
        host: db_config['host'],
        username: db_config['username'],
        password: db_config['password'],
        database: db_config['database']
      )

      case table_name
      when "t_customers"
        if id.nil?
          # Insert new customer
          myQuery = "INSERT INTO #{table_name} (name, street, housenumber, zip, city, email, phone) VALUES (?, ?, ?, ?, ?, ?, ?);"
          stmt = client.prepare(myQuery)
          stmt.execute(
            values[:name],
            values[:street],
            values[:housenumber],
            values[:zip],
            values[:city],
            values[:email],
            values[:phone]
          )
          @statusbar.push(@statusbar.get_context_id('info'), "Kundendaten gespeichert")
        else
          # Update existing customer
          set_clause = values.map { |k, v| "#{k}=?" }.join(', ')
          myQuery = "UPDATE #{table_name} SET #{set_clause} WHERE customer_id=?"
          stmt = client.prepare(myQuery)
          stmt.execute(*values.values, id)
          @statusbar.push(@statusbar.get_context_id('info'), "Kundendaten aktualisiert")
        end
      when "t_products"
        if id.nil?
          # Insert new product
          myQuery = "INSERT INTO #{table_name} (name, brutto, stored, tax, tosell) VALUES (?, ?, ?, ?, ?);"
          stmt = client.prepare(myQuery)
          stmt.execute(
            values[:name],
            values[:price],
            values[:stock],
            values[:vat],
            values[:tosell]
          )
          @statusbar.push(@statusbar.get_context_id('info'), "Produktdaten gespeichert")
        else
          # Update existing product
          set_clause = values.map { |k, v| "#{k}=?" }.join(', ')
          myQuery = "UPDATE #{table_name} SET #{set_clause} WHERE product_id=?"
          stmt = client.prepare(myQuery)
          stmt.execute(*values.values, id)
          @statusbar.push(@statusbar.get_context_id('info'), "Produktdaten aktualisiert")
        end
      when "t_invoices"
        if id.nil?
          # Insert new invoice
          myQuery = "INSERT INTO #{table_name} (sum, date, customer_id, invoice_number) VALUES (?, ?, ?, ?);"
          stmt = client.prepare(myQuery)
          stmt.execute(
            values[:sum],
            values[:date],
            values[:customer_id],
            values[:invoice_number]
          )
          @statusbar.push(@statusbar.get_context_id('info'), "Rechnung gespeichert")
        else
          # Update invoice
          myQuery = "UPDATE #{table_name} SET paid = #{values[:paid]} WHERE invoice_number = #{id}"
          stmt = client.prepare(myQuery)
          stmt.execute
          @statusbar.push(@statusbar.get_context_id('info'), "Rechnung aktualisiert")
        end
      when "t_billed_products"
        if id.nil?
          # Billed products
          myQuery = "INSERT INTO #{table_name} (invoice_id, product_id, product_count) VALUES (?, ?, ?);"
          stmt = client.prepare(myQuery)
          stmt.execute(
            values[:invoice_id],
            values[:product_id],
            values[:product_count]
          )
        end
        # Add cases for other tables as needed
      end

      refresh_current_tab

    rescue Mysql2::Error => e
      puts "Fehler beim Verbinden zur Datenbank: #{e.message}"
    ensure
      client.close if client
    end
  end
    
  def generate_pdf(invoice_id, customer_id, selected_products, date)
    config = load_config
    pdf_path = config['pdf_path']
    logo_path = config['logo']
    company = config['company']

    customer_data = get_from_DB("SELECT name, street, housenumber, zip, city, email, phone FROM t_customers WHERE customer_id = #{customer_id}", false).first

    billed_products = get_from_DB("SELECT p.name, bp.product_count, p.brutto, (p.brutto * bp.product_count) as total, p.tax
                                 FROM t_billed_products bp 
                                 JOIN t_products p ON bp.product_id = p.product_id 
                                 WHERE bp.invoice_id = #{invoice_id}", false)

                              
    invoice_number = get_from_DB("SELECT invoice_number FROM t_invoices WHERE invoice_id = #{invoice_id}", false).first['invoice_number']

    pdf_file_path = File.join(pdf_path, "Rechnung_#{invoice_number}.pdf")

    Prawn::Fonts::AFM.hide_m17n_warning = true
    Prawn::Document.generate(pdf_file_path) do |pdf|
      pdf.font "Helvetica"

      # Wasserzeichen hinzufügen
      if File.exist?(logo_path)
        pdf.canvas do
          pdf.transparent(0.5) do
            pdf.image logo_path, at: [pdf.bounds.width / 2 - 100, pdf.bounds.height / 2 + 100], width: 200, height: 200
          end
        end
      end

      # Company information
      pdf.text "#{company['name']}", style: :bold
      pdf.text "#{company['street']}"
      pdf.text "#{company['city']}"
      pdf.move_down 20

      # Customer address
      pdf.text "Rechnung an:", style: :bold
      pdf.text customer_data['name'], size: 12
      pdf.text "#{customer_data['street']} #{customer_data['housenumber']}", size: 12
      pdf.text "#{customer_data['zip']} #{customer_data['city']}", size: 12
      pdf.move_down 15
      
      if customer_data['email'] && !customer_data['email'].empty?
        pdf.text "E-Mail: #{customer_data['email']}"
      end

      pdf.move_down 25
  
      pdf.text "Rechnung Nr. #{invoice_number}", size: 16, style: :bold
      year, month, day = date.split('-')

      # Baue den neuen String im Format Tag.Monat.Jahr
      pdf.move_down 10
      formatted_date = [day, month, year].join('.')
      pdf.text "Datum: #{formatted_date}"
      pdf.move_down 20

      # Rechnungspositionen
        items = [["Produkt", "Menge", "Einzelpreis (Brutto)", "Einzelpreis (Netto)", "MwSt (%)", "Gesamt (Brutto)"]]
        total_netto = 0.0
        total_mwst = 0.0
        total_brutto = 0.0

      # Invoice items
      billed_products.each do |product|
        tmp = product['tax'] + 100
        mwst = product['brutto'] / tmp * product['tax']
        netto = product['brutto'] / tmp * 100
        total_netto += netto * product['product_count']
        total_mwst += mwst * product['product_count']
        total_brutto += product['total']

        items << [
          product['name'],
          product['product_count'],
          sprintf("%.2f €", product['brutto']),
          sprintf("%.2f €", netto),
          sprintf("%.2f %%", product['tax']), # Hier wird das Prozentzeichen verwendet
          sprintf("%.2f €", product['total'])
      ]
    end


  # Festgelegte Spaltenbreiten
  column_widths = [185, 55, 75, 75, 75, 75]

      pdf.table(items, header: true, width: pdf.bounds.width, cell_style: { inline_format: true }, column_widths: column_widths) do
        row(0).font_style = :bold
        columns(2..5).align = :right
      end


      pdf.move_down 10
      pdf.text "Nettobetrag: #{sprintf("%.2f €", total_netto)}", align: :right
      pdf.text "MwSt: #{sprintf("%.2f €", total_mwst)}", align: :right
      pdf.text "Gesamtbetrag: #{sprintf("%.2f €", total_brutto)}", size: 16, style: :bold, align: :right

      pdf.move_down 40
      #pdf.text "Betrag dankend erhalten!", align: :center

      qr_code_base64 = generate_sepa_qr_code(
        "#{company['name']}",    # Name des Empfängers
        "#{company['iban']}", # IBAN
        "#{company['bic']}",      # BIC
        "#{total_brutto.to_f}",           # Betrag
        "#{invoice_number}" # Verwendungszweck
        )


      # QR-Code und Text in einer Bounding Box einfügen
      pdf.bounding_box([pdf.bounds.right - 120, pdf.bounds.bottom + 150], width: 120) do
        #pdf.text "Scannen zum Bezahlen:", align: :right
        pdf.text "Betrag dankend erhalten!", align: :center
        qr_code_image = StringIO.new(Base64.decode64(qr_code_base64))
        pdf.image qr_code_image, width: 100, position: :center
      end
     

      pdf.repeat(:all) do
        pdf.bounding_box([0, pdf.bounds.bottom + 20], width: pdf.bounds.width, height: 30) do
          pdf.stroke_horizontal_rule
          pdf.move_down 5
          pdf.text "|#{company['name']} | #{company['street']}, #{company['city']} |", size: 8, align: :center
          pdf.text "IBAN: #{company['iban']}| BIC: #{company['bic']}", size: 8, align: :center
        end
      end

    end
  end

  def generate_sepa_qr_code(name, iban, bic, amount, reference)
    # SEPA QR-Code Format erstellen
    sepa_data = <<-SEPA.strip
      BCD
      002
      1
      SCT
      #{bic}
      #{name}
      #{iban}
      #{amount}
      EUR
      #{reference}
    SEPA

    qr = RQRCode::QRCode.new(sepa_data, level: :l, size: 6)
    png = qr.as_png
    Base64.encode64(png.to_s) # Bild in Base64 kodieren, um es in ein PDF einzufügen
  end



  def run
    Gtk.main
  end
end

app = InvoiceManager.new
app.run
