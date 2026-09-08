class AddMobileLibraryToSpecialDates < ActiveRecord::Migration[8.1]
  def change
    add_reference :special_dates, :mobile_library, null: true, foreign_key: true
  end
end
