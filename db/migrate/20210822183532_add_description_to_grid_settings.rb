class AddDescriptionToGridSettings < ActiveRecord::Migration[6.1]
  def change
    add_column :grid_settings, :description, :string
  end
end
