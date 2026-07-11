class CreateMobileLibraryStaffAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :mobile_library_staff_assignments do |t|
      t.references :mobile_library_route, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.timestamps
    end
  end
end
