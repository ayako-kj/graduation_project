Admin.where(library_id: nil).destroy_all

library = Library.find_or_create_by!(name: "サンプル図書館")

admin = Admin.find_or_initialize_by(email: 'admin@pitat.com')
admin.password = 'password123' if admin.new_record?
admin.password_confirmation = 'password123' if admin.new_record?
admin.library ||= library
admin.save!

%w[館長 副館長 司書 行政職 一般事務 専門司書].each_with_index do |name, index|
  st = StaffType.find_or_create_by!(name: name)
  st.update_column(:sort_order, index + 1)
end

%w[正規職員 会計年度任用職員].each do |name|
  EmploymentType.find_or_create_by!(name: name)
end
