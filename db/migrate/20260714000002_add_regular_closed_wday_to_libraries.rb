class AddRegularClosedWdayToLibraries < ActiveRecord::Migration[7.2]
  def change
    # 0=日 1=月 2=火 3=水 4=木 5=金 6=土、nilは定休曜日なし
    add_column :libraries, :regular_closed_wday, :integer, default: 2
  end
end
