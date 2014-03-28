require "csv"

class ValidatorController < ApplicationController
  # Validate action
  #
  # For example:
  #   http://localhost:3000/validate?url=https://dl.dropboxusercontent.com/u/893551/pracovni/OPLZZ_2013/validator/data/validator/examples/Filip_Podstavec_3.html
  #   curl -H "Accept:application/json" --data-urlencode "text@data/validator/examples/Triplethink_4.html" http://localhost:3000/validate
  def validate
    webpage = Webpage.new params
    # Note: webpage.valid? needs to be called, validation is lazy!
    valid = webpage.valid?
    errors = webpage.errors.messages 

    # Log request and its results
    log_line = [
                request.remote_ip,
                request.env["HTTP_USER_AGENT"],
                webpage.hashed_content,
                valid ? webpage.content : nil,
                JSON.generate(errors)
              ].to_csv
    logger.validator.info log_line

    respond_to do |format|
      format.html do
        # Redirect to index if there are non-recoverable errors
        if error = (errors[:input] || errors[:syntax] || errors[:sparql])
          flash.now[:error] = error.first
          render "index"
        else
          @errors = valid ? [] : errors[:validation].first
          @job_postings = webpage.job_postings 
          render "validate"
        end
      end
      format.any(:json, :jsonld) do
        render json: errors, callback: params["callback"]
      end
    end
  end
end
