class StaffsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_staff, only: %i[edit update destroy move_up move_down regenerate_token]

  def index
    @staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:sort_order, :id)
  end

  def new
    @staff = current_library.staffs.build
    set_form_options
  end

  def create
    @staff = current_library.staffs.build(staff_params)
    @staff.sort_order = current_library.staffs.maximum(:sort_order).to_i + 1
    if @staff.save
      update_assignments(@staff)
      redirect_to staffs_path, notice: "職員を登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @staff.update(staff_params)
      update_assignments(@staff)
      redirect_to staffs_path, notice: "職員情報を更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @staff.destroy
    redirect_to staffs_path, notice: "#{@staff.name}を削除しました。"
  end

  def move_up
    above = current_library.staffs.where("sort_order < ?", @staff.sort_order).order(sort_order: :desc).first
    swap_sort_order(@staff, above) if above
    redirect_to staffs_path
  end

  def move_down
    below = current_library.staffs.where("sort_order > ?", @staff.sort_order).order(sort_order: :asc).first
    swap_sort_order(@staff, below) if below
    redirect_to staffs_path
  end

  def hope_urls
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @base_url = request.base_url
  end

  def special_date_urls
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @base_url = request.base_url
  end

  def special_date_qrcodes
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    base_url = request.base_url
    @qr_data = @staffs.each_with_object({}) do |staff, h|
      url = "#{base_url}/special?token=#{staff.access_token}"
      h[staff.id] = { url: url, svg: build_qr_svg(url) }
    end
    @library_name = current_library.name
  end

  def hope_qrcodes
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    base_url = request.base_url
    @qr_data = @staffs.each_with_object({}) do |staff, h|
      url = "#{base_url}/hope?token=#{staff.access_token}"
      h[staff.id] = { url: url, svg: build_qr_svg(url) }
    end
    @library_name = current_library.name
  end

  def combined_qrcodes
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    base_url = request.base_url
    @qr_data = @staffs.each_with_object({}) do |staff, h|
      hope_url    = "#{base_url}/hope?token=#{staff.access_token}"
      special_url = "#{base_url}/special?token=#{staff.access_token}"
      h[staff.id] = {
        hope_svg:    build_qr_svg(hope_url),
        special_svg: build_qr_svg(special_url)
      }
    end
    @library_name = current_library.name
  end

  def regenerate_token
    @staff.regenerate_token!
    redirect_to hope_urls_staffs_path, notice: "#{@staff.name}のURLを再発行しました。"
  end

  private

  def swap_sort_order(a, b)
    a_order = a.sort_order
    a.update_column(:sort_order, b.sort_order)
    b.update_column(:sort_order, a_order)
  end

  def build_qr_svg(url)
    offset      = 16
    module_size = 4
    qr          = RQRCode::QRCode.new(url, level: :l)
    total_size  = qr.modules.length * module_size + offset * 2
    svg = qr.as_svg(
      offset: offset, color: "000", shape_rendering: "crispEdges",
      module_size: module_size, standalone: true
    )
    # viewBox を付与してCSSによるスケーリングを有効にする
    svg.sub("<svg ", %(<svg viewBox="0 0 #{total_size} #{total_size}" ))
  end

  def set_staff
    @staff = current_library.staffs.find(params[:id])
  end

  def set_form_options
    @staff_types = StaffType.order(:sort_order, :id)
    @employment_types = EmploymentType.all
    @assignments = current_library.assignments.order(:id)
  end

  def update_assignments(staff)
    ids = params.dig(:staff, :assignment_ids)&.reject(&:blank?)&.map(&:to_i) || []
    staff.assignments = current_library.assignments.where(id: ids)
  end

  def staff_params
    raw = params.require(:staff).permit(:name, :staff_type_id, :employment_type_id, :weekly_work_days,
                                        :daily_work_hours, unavailable_wdays: [])
    wdays = Array(raw.delete(:unavailable_wdays)).reject(&:blank?).map(&:to_i)
    raw.merge(unavailable_wdays: wdays.to_json)
  end
end
