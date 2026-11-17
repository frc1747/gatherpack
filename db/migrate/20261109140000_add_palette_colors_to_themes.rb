class AddPaletteColorsToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :brand_color, :string
    add_column :themes, :background_color, :string
    add_column :themes, :surface_color, :string
    add_column :themes, :text_color, :string
  end
end
