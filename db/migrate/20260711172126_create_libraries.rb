class CreateLibraries < ActiveRecord::Migration[7.2]
  def change
    create_table :libraries do |t|
      t.string :name, null: false

      t.timestamps
    end
  end
end
