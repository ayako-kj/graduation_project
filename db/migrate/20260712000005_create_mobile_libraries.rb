class CreateMobileLibraries < ActiveRecord::Migration[7.2]
  def change
    create_table :mobile_libraries do |t|
      t.references :library, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
  end
end
