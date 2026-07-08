class StaffMasker
  def initialize(staffs)
    @mask_map = {}
    @reverse_map = {}
    staffs.each_with_index do |staff, index|
      identifier = "Staff_#{(65 + index).chr}"
      @mask_map[staff.name] = identifier
      @reverse_map[identifier] = staff.name
    end
  end

  def mask(name)
    @mask_map[name] || name
  end

  def unmask(identifier)
    @reverse_map[identifier] || identifier
  end

  def mask_map
    @mask_map.dup
  end

  def unmask_text(text)
    @reverse_map.reduce(text) do |result, (identifier, real_name)|
      result.gsub(identifier, real_name)
    end
  end
end
