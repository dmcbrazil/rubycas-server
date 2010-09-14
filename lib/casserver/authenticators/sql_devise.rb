require 'casserver/authenticators/sql'

require File.dirname(__FILE__) + '/devise_encryptors/bcrypt'
require File.dirname(__FILE__) + '/devise_encryptors/restful_authentication_sha1'

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
#   sha1_stretches: 10
#   bcrypt_stretches: 10
#   encryptor: Bcrypt
#   stretches: (same as config.stretches in config/initializers/devise.rb)
#   pepper:    (same as config.pepper    in config/initializers/devise.rb)
#   rest_auth_site_key: REST_AUTH_SITE_KEY from Restful Authentication
#   extra_attributes: authentication_token
#
#
class CASServer::Authenticators::SQLDevise < CASServer::Authenticators::SQL

  def validate(credentials)
    read_standard_credentials(credentials)
    raise_if_not_configured

    user_model = self.class.user_model

    @options[:username_column]  ||= "username"
    @options[:email_column]     ||= "email"
    @options[:password_column]  ||= "encrypted_password"
    @options[:salt_column]      ||= "password_salt"

    $LOG.debug "#{self.class}: [#{user_model}] " + "Connection pool size: #{user_model.connection_pool.instance_variable_get(:@checked_out).length}/#{user_model.connection_pool.instance_variable_get(:@connections).length}"
    
    results = user_model.find(:all, :conditions => ["#{@options[:username_column]} = ? or #{@options[:email_column]} = ?", @username, @username])
    user_model.connection_pool.checkin(user_model.connection)

    return false if results.size <= 0

    $LOG.warn("Multiple matches found for user '#{@username}'") if results.size > 1
    user = results.first

    encrypted_password = encrypt_password user

    return false if encrypted_password != user.encrypted_password

    re_encrypt_password user
    extract_extra_attributes results
    true
  end

  protected
    def encrypt_password user
      if user.last_sign_in_at.blank?
        encryptor = Devise::Encryptors::RestfulAuthenticationSha1
        stretches = @options[:sha1_stretches]
        pepper = @options[:rest_auth_site_key]
      else
        encryptor = Devise::Encryptors::Bcrypt
        stretches = @options[:bcrypt_stretches]
        pepper = @options[:pepper]
      end
      result = encryptor.digest @password, stretches, user.send(@options[:salt_column]), pepper
      result
    end

    def re_encrypt_password user
      user.send("#{@options[:salt_column]}=", Devise::Encryptors::Bcrypt.salt(@options[:bcrypt_stretches])) if user.last_sign_in_at.blank?
      user.last_sign_in_at = Time.now
      user.current_sign_in_at = user.last_sign_in_at
      user.sign_in_count += 1
      user.encrypted_password = encrypt_password(user)
      user.save
    end

    def extract_extra_attributes results
      unless @options[:extra_attributes].blank?
        if results.size > 1
          $LOG.warn("#{self.class}: Unable to extract extra_attributes because multiple matches were found for #{@username.inspect}")
        else
          extract_extra(results.first)
          log_extra
        end
      end
    end
end

