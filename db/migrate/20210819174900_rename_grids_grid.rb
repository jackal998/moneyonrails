class RenameGridsGrid < ActiveRecord::Migration[6.1]
  def change
    rename_column :grid_settings, :girds, :grids
  end
end
