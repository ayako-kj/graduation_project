class AddAccessTokenToStaffs < ActiveRecord::Migration[7.2]
  def up
    add_column :staffs, :access_token, :string
    add_index :staffs, :access_token, unique: true

    Staff.find_each { |s| s.update_column(:access_token, SecureRandom.urlsafe_base64(16)) }
  end

  def down
    remove_column :staffs, :access_token
  end
end
