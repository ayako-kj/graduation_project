class AddWorkHoursToEmploymentTypesAndStaffs < ActiveRecord::Migration[7.2]
  def up
    add_column :employment_types, :daily_work_hours, :decimal, precision: 4, scale: 2, default: 7.5, null: false
    add_column :employment_types, :city_hall_daily_hours, :decimal, precision: 4, scale: 2, default: 6.0, null: false
    add_column :employment_types, :is_regular, :boolean, default: false, null: false

    # 既存の正規職員レコードに正しい値を設定
    EmploymentType.where(name: "正規職員").update_all(
      daily_work_hours: 7.75,
      city_hall_daily_hours: 7.75,
      is_regular: true
    )
    EmploymentType.where(name: "会計年度任用職員").update_all(
      daily_work_hours: 7.5,
      city_hall_daily_hours: 6.0,
      is_regular: false
    )

    add_column :staffs, :daily_work_hours, :decimal, precision: 4, scale: 2
  end

  def down
    remove_column :employment_types, :daily_work_hours
    remove_column :employment_types, :city_hall_daily_hours
    remove_column :employment_types, :is_regular
    remove_column :staffs, :daily_work_hours
  end
end
