class ValidatorController < ApplicationController
  before_filter :set_locale

  # Validate action
  #
  # For example:
  #   http://localhost:3000/?url=https://dl.dropboxusercontent.com/u/893551/pracovni/OPLZZ_2013/validator-web/data/validator/examples/Filip_Podstavec_3.html
  #   curl --data-urlencode "data@data/validator/examples/Triplethink_4.html" http://localhost:3000/
  def validate
    webpage = Webpage.new(params)
    # Note: webpage.valid? needs to be called, validation is lazy!
    valid = webpage.valid?
    errors = webpage.errors.messages 

    # Redirect to index if there are non-recoverable errors
    if error = (errors[:input] || errors[:syntax] || errors[:sparql])
      flash.now[:error] = error.first
      render "index"
    else
      @errors = valid ? [] : errors[:validation].first
      @job_postings = webpage.job_postings 
      render "preview"
    end
  end
  
  private

  def set_locale
    I18n.locale = http_accept_language.compatible_language_from(I18n.available_locales)
  end
end
