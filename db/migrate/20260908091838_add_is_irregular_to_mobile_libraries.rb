class AddIsIrregularToMobileLibraries < ActiveRecord::Migration[8.1]
  def change
    add_column :mobile_libraries, :is_irregular, :boolean, default: false, null: false
  end
end
