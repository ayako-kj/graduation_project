library = Library.find_or_create_by!(name: "サンプル図書館")

admin = Admin.find_or_initialize_by(email: 'admin@pitat.com')
admin.password = 'password123' if admin.new_record?
admin.password_confirmation = 'password123' if admin.new_record?
admin.library ||= library
admin.save!

Admin.where(library_id: nil).find_each do |a|
  a.update!(library: library)
end

%w[館長 副館長 専門司書 司書 行政職 一般事務].each do |name|
  StaffType.find_or_create_by!(name: name)
end

%w[正規職員 会計年度任用職員].each do |name|
  EmploymentType.find_or_create_by!(name: name)
end
