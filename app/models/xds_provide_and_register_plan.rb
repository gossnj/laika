class XdsProvideAndRegisterPlan < XdsPlan
  test_name 'XDS Provide & Register'
  pending_actions 'checklist' => :xds_checklist, 'execute' => :xds_select_document
  completed_actions 'inspect' => :xds_inspect

  def validate_xds_metadata metadata_of_interest
    if metadata_of_interest
      validator = Validators::XdsMetadataValidator.new
      validation_errors = validator.validate test_type_data, metadata_of_interest
      if validation_errors.empty?
        content_errors.clear
        pass
      else
        content_errors << validation_errors
        fail
      end
      cdoc = ClinicalDocument.new \
        :uploaded_data => XDSUtils.retrieve_document(metadata_of_interest)
      update_attributes :clinical_document => cdoc
    else
      content_errors << ContentError.new(
        :error_message => "Unable to find metadata in the XDS Registry",
        :validator => "XDS Metadata Validator",
        :inspection_type => 'XDS Provide and Register')
      fail
    end
  end

  module Actions
    def xds_select_document
      @metadata = test_plan.fetch_xds_metadata patient.patient_identifier
    end

    def xds_compare
      metadata = YAML.load(params[:test_type_data])
      test_plan.validate_xds_metadata metadata
      render 'test_plans/xds_inspect'
    end

    def xds_inspect
    end
  end
end
