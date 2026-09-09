class SpecialDatesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_special_date, only: %i[edit update destroy]

  TARGET_GROUPS = SpecialDate::TARGET_GROUPS

  def index
    @target_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month.next_month
    @special_dates = current_library.special_dates
                       .includes(:designated_staffs, :created_by_staff, :mobile_library)
                       .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                       .order(:date)

    staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:sort_order, :id)
    @special_dates_by_staff = staffs.filter_map do |staff|
      matched = @special_dates.select { |sd| special_date_applies_to?(sd, staff) }
      [staff, matched] if matched.any?
    end
  end

  def new
    @special_date = current_library.special_dates.build(date: Date.today.beginning_of_month.next_month)
    set_form_options
  end

  def create
    @special_date = current_library.special_dates.build(special_date_params)
    @special_date.designated_staff_ids_input = designated_staff_ids_param
    if @special_date.save
      sync_designated_staffs
      redirect_to special_dates_path(month: @special_date.date.strftime("%Y-%m")), notice: "スケジュールを登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    @special_date.designated_staff_ids_input = designated_staff_ids_param
    if @special_date.update(special_date_params)
      sync_designated_staffs
      redirect_to special_dates_path(month: @special_date.date.strftime("%Y-%m")), notice: "スケジュールを更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @special_date.destroy
    redirect_to special_dates_path(month: @special_date.date.strftime("%Y-%m")), notice: "#{@special_date.label}を削除しました。"
  end

  def export
    @target_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month.next_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a

    holidays = HolidayFetcher.fetch(@target_month.year)
    wdays = current_library.closed_wdays_array
    extra = temporary_closed_dates_map(current_library, @target_month)
    forced_open = temporary_open_dates_map(current_library, @target_month)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays,
                     closed_wdays: wdays, extra_closed_dates: extra, forced_open_dates: forced_open).closed_days_with_labels

    special_dates = current_library.special_dates
                      .includes(:designated_staffs, :mobile_library)
                      .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                      .order(:date)

    # 個別スケジュール：あおばな号等の不定期移動図書館に紐付かないもの
    @individual_lines = Hash.new { |h, k| h[k] = [] }
    special_dates.reject { |sd| sd.mobile_library_id.present? }.each do |sd|
      target = sd.target_group.presence || (sd.designated_staffs.any? ? sd.designated_staffs.map(&:name).join("・") : nil)
      line = [sd.time_range_label, sd.label].compact_blank.join(" ")
      line += "〔#{target}〕" if target
      @individual_lines[sd.date] << line
    end

    # 不定期移動図書館ごとの列（あおばな号等）：現状登録されている全ての
    # 不定期移動図書館を列として表示する
    @irregular_libraries = current_library.mobile_libraries.where(is_irregular: true).order(:id)
    @irregular_lines = @irregular_libraries.each_with_object({}) do |ml, h|
      h[ml.id] = Hash.new { |hash, k| hash[k] = [] }
    end
    special_dates.select { |sd| sd.mobile_library_id.present? }.each do |sd|
      next unless @irregular_lines.key?(sd.mobile_library_id)
      staff_names = sd.designated_staffs.map(&:name).join("・")
      line = [sd.time_range_label, sd.label].compact_blank.join(" ")
      line += "〔#{staff_names}〕" if staff_names.present?
      @irregular_lines[sd.mobile_library_id][sd.date] << line
    end

    # 移動図書館（定例巡回）
    @mobile_lines = Hash.new { |h, k| h[k] = [] }
    current_library.mobile_libraries.where(is_irregular: false)
                    .includes(mobile_library_routes: [:staffs, :mobile_library_exceptions]).each do |ml|
      ml.mobile_library_routes.each do |route|
        occurrence = route.occurrence_for(@target_month, closed_days: @closed_days)
        next if occurrence.nil?
        staff_names = occurrence.staffs.map(&:name).join("・")
        line = "#{ml.name}#{route.name}"
        line += "〔#{staff_names}〕" if staff_names.present?
        @mobile_lines[occurrence.date] << line
      end
    end

    filename = "行事予定表_#{@target_month.strftime('%Y年%m月')}.xlsx"
    response.headers["Content-Disposition"] = "attachment; filename*=UTF-8''#{ERB::Util.url_encode(filename)}"
    render "export", formats: [:xlsx]
  end

  private

  def set_special_date
    @special_date = current_library.special_dates.find(params[:id])
  end

  def set_form_options
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @assignments = current_library.assignments.includes(:staffs).order(:sort_order, :id)
    @irregular_mobile_libraries = current_library.mobile_libraries.where(is_irregular: true).order(:id)
  end

  def sync_designated_staffs
    @special_date.designated_staffs = Staff.where(id: designated_staff_ids_param.map(&:to_i))
  end

  def designated_staff_ids_param
    Array(params.dig(:special_date, :designated_staff_ids)).reject(&:blank?)
  end

  def special_date_params
    params.require(:special_date).permit(:date, :label, :target_group, :start_time, :end_time, :mobile_library_id)
  end

  # 指定した職員が、そのスケジュールの対象かどうか
  # （対象グループ一致、または個別指定職員に含まれる）
  def special_date_applies_to?(special_date, staff)
    case special_date.target_group
    when "全職員"
      return true
    when "正規職員"
      return true if staff.employment_type.is_regular
    when nil, ""
      # 対象グループの指定なし（個別指定のみ）
    else
      return true if special_date.target_group == staff.staff_type.name
    end
    special_date.designated_staffs.include?(staff)
  end
end
