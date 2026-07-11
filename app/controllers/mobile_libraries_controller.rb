class MobileLibrariesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_mobile_library, only: %i[show edit update destroy]

  def index
    @mobile_libraries = current_library.mobile_libraries
                                       .includes(mobile_library_routes: :staffs)
                                       .order(:id)
  end

  def show
    @routes = @mobile_library.mobile_library_routes
                             .includes(:staffs)
                             .order(:wday, :week_number)
  end

  def new
    @mobile_library = current_library.mobile_libraries.build
  end

  def create
    @mobile_library = current_library.mobile_libraries.build(mobile_library_params)
    if @mobile_library.save
      redirect_to mobile_library_path(@mobile_library), notice: "移動図書館を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mobile_library.update(mobile_library_params)
      redirect_to mobile_library_path(@mobile_library), notice: "移動図書館名を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @mobile_library.name
    @mobile_library.destroy
    redirect_to mobile_libraries_path, notice: "#{name}を削除しました。"
  end

  private

  def set_mobile_library
    @mobile_library = current_library.mobile_libraries.find(params[:id])
  end

  def mobile_library_params
    params.require(:mobile_library).permit(:name)
  end
end
