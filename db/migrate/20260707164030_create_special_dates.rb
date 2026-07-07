class CreateSpecialDates < ActiveRecord::Migration[7.2]
  def change
    create_table :special_dates do |t|
      t.date :date
      t.string :label
      t.string :target_group

      t.timestamps
    end
  end
end
