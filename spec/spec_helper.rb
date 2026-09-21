require "active_record"
require "arel_where"
ActiveRecord::Base.establish_connection(ENV.fetch("TEST_DATABASE_URL", "postgresql:///postgres"))
RSpec.configure do |config|
  config.after(:suite) { ActiveRecord::Base.connection_pool.disconnect! }
end
connection = ActiveRecord::Base.connection
connection.execute("CREATE TEMP TABLE organisations (id bigserial PRIMARY KEY)")
connection.execute("CREATE TEMP TABLE users (id bigserial PRIMARY KEY, organisation_id bigint, first_name text, last_name text, date_of_birth date, active boolean)")
connection.execute("CREATE TEMP TABLE emails (id bigserial PRIMARY KEY, address text)")
class Organisation < ActiveRecord::Base; end
class User < ActiveRecord::Base
  belongs_to :organisation
end
class Email < ActiveRecord::Base; end
module FixtureRecords
  def create(kind, **attributes)
    { organisation: Organisation, user: User, email: Email }.fetch(kind).create!(attributes)
  end
end
RSpec.configure do |config|
  config.include FixtureRecords
  config.before { User.delete_all; Organisation.delete_all; Email.delete_all }
end
