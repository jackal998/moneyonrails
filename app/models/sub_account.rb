class SubAccount < ApplicationRecord
  belongs_to :user

  validates_presence_of :user_id, :name, :application, :encrypted_public_key, :encrypted_secret_key

  validates_uniqueness_of :name, :scope => :user_id
  validates_uniqueness_of :application, :scope => :user_id

  validates_inclusion_of :application, :in => ["Funding", "Grid"]
end
