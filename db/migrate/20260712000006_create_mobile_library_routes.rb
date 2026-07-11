class CreateMobileLibraryRoutes < ActiveRecord::Migration[7.2]
  def change
    create_table :mobile_library_routes do |t|
      t.references :mobile_library, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :wday, null: false
      t.integer :week_number, null: false
      t.timestamps
    end
  end
end
