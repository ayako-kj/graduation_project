class CreateEmploymentTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :employment_types do |t|
      t.string :name

      t.timestamps
    end
  end
end
