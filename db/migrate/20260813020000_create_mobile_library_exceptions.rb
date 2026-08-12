class CreateMobileLibraryExceptions < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_library_exceptions do |t|
      t.references :mobile_library_route, null: false, foreign_key: true
      t.date :target_month, null: false
      t.date :date

      t.timestamps
    end
    add_index :mobile_library_exceptions, [:mobile_library_route_id, :target_month],
              unique: true, name: "index_ml_exceptions_on_route_and_month"

    create_table :mobile_library_exception_staffs do |t|
      t.references :mobile_library_exception, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true

      t.timestamps
    end
  end
end
