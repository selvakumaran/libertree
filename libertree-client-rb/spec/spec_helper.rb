if ENV['LIBERTREE_ENV'] != 'test'
  $stderr.puts "Refusing to run specs in a non-test environment.  Comment out the exit line if you know what you're doing."
  exit 1
end

require 'libertree/db'

########################
# FIXME: M4DBI wants us to connect to the db before defining models.  As model
# definitions are loaded when 'libertree/server' is required, we have to do
# this first.
Libertree::DB.load_config "#{File.dirname( __FILE__ ) }/../database.yaml"
Libertree::DB.dbh
########################

require 'libertree/model'
require_relative 'factories'
