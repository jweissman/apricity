require "active_record"

class User < ActiveRecord::Base
  def self.table_name = "users"

  def name_upcased = name.upcase
end