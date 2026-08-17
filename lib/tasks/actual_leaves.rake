namespace :actual_leaves do
  desc "希望休（年休・夏期休暇・病気休暇・特別休暇）から実績（ActualLeave）が未登録の日を一括で補完する（既存の実績は上書きしない）"
  task sync_from_requests: :environment do
    reason_to_type = {
      "年休" => "annual",
      "夏期休暇" => "summer",
      "病気休暇" => "sick",
      "特別休暇" => "special"
    }

    created = 0
    LeaveRequest.where(reason: reason_to_type.keys).find_each do |lr|
      next if ActualLeave.exists?(staff_id: lr.staff_id, date: lr.date)
      ActualLeave.create!(staff_id: lr.staff_id, date: lr.date, leave_type: reason_to_type[lr.reason])
      created += 1
    end
    puts "[actual_leaves:sync_from_requests] #{created}件の実績を補完しました"
  end
end
