formatter = Proc.new { |_, time, _, msg|
  "#{time.to_datetime.xmlschema},#{msg.to_s.strip}\n" 
}

MultiLogger.add_logger("validator", formatter: formatter, path: "validator_#{Rails.env}")
