class BackfillLeaveRequestActualLeaveSync < ActiveRecord::Migration[8.1]
  # LeaveRequest / ActualLeave の双方向自動同期（モデルのコールバック）を
  # 追加する前から存在していたレコードには同期が効いていないため、
  # 既存データにも同じ同期ロジックを一括で適用する。
  # saveはレコードに変更が無くてもコールバックを発火させるため、
  # 各モデルに定義済みの同期コールバックがそのまま使える
  def up
    ActualLeave.find_each(&:save)
    LeaveRequest.find_each(&:save)
  end

  def down
    # データ移行のため、戻す処理はなし
  end
end
