class MobileLibraryStaffAssignment < ApplicationRecord
  belongs_to :mobile_library_route
  belongs_to :staff
end
