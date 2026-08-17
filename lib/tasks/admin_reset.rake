namespace :admin do
  desc "RESET_ADMIN_EMAIL / RESET_ADMIN_PASSWORD が設定されている時だけ、該当する管理者のパスワードをリセットする（未設定時は何もしない）"
  task reset_password: :environment do
    email = ENV["RESET_ADMIN_EMAIL"].presence
    password = ENV["RESET_ADMIN_PASSWORD"].presence

    if email.nil? || password.nil?
      next
    end

    admin = Admin.find_by(email: email)
    if admin.nil?
      puts "[admin:reset_password] 該当する管理者が見つかりません: #{email}"
      next
    end

    admin.update!(password: password, password_confirmation: password)
    puts "[admin:reset_password] パスワードを更新しました: #{email}"
  end
end
