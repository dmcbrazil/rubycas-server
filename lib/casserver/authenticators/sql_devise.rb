require 'casserver/authenticators/sql'

require File.dirname(__FILE__) + '/devise_encryptors/bcrypt'

begin
  require 'active_record'
rescue LoadError
  require 'rubygems'
  require 'active_record'
end

# This is a version of the SQL authenticator that works with Devise configured to use Bcrypt.
# Before using this, you MUST configure Devise to use Bcrypt and set the same values for config.stretches and config.pepper in config/initializers/devise.rb.
# config.
#
# If you need more info on how to use Devise:
#
# * git://github.com/plataformatec/devise.git
#
# Usage:

# authenticator:
#   class: CASServer::Authenticators::SQLDevise
#   database:
#     adapter: mysql
#     database: some_database_with_users_table
#     user: root
#     password:
#     server: localhost
#   user_table: users
#   username_column: username
#   email_column: email
#   password_column: encrypted_password
#   salt_column: password_salt
#   encryptor: Bcrypt
#   stretches: (same as config.stretches in config/initializers/devise.rb)
#   pepper:    (same as config.pepper    in config/initializers/devise.rb)
#   extra_attributes: authentication_token
#
class CASServer::Authenticators::SQLDevise < CASServer::Authenticators::SQL

  def validate(credentials)
    read_standard_credentials(credentials)
    raise_if_not_configured

    user_model = self.class.user_model

    username_column = @options[:username_column]  || "username"
    email_column    = @options[:email_column]     || "email"
    password_column = @options[:password_column]  || "encrypted_password"
    salt_column     = @options[:salt_column]      || "password_salt"

    $LOG.debug "#{self.class}: [#{user_model}] " + "Connection pool size: #{user_model.connection_pool.instance_variable_get(:@checked_out).length}/#{user_model.connection_pool.instance_variable_get(:@connections).length}"
    
    results = user_model.find(:all, :conditions => ["#{username_column} = ? or #{email_column} = ?", @username, @username])
    user_model.connection_pool.checkin(user_model.connection)

    encryptor = Devise::Encryptors::Bcrypt

    if results.size > 0
      $LOG.warn("Multiple matches found for user '#{@username}'") if results.size > 1
      user = results.first
      
      unless @options[:extra_attributes].blank?
        if results.size > 1
          $LOG.warn("#{self.class}: Unable to extract extra_attributes because multiple matches were found for #{@username.inspect}")
        else
          extract_extra(user)
          log_extra
        end
      end

      return encryptor.digest(@password, @options[:stretches], user.send(salt_column), @options[:pepper]) == user.send(password_column)
    else
      return false
    end
  end
end

