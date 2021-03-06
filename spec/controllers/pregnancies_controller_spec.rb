require File.dirname(__FILE__) + '/../spec_helper'

describe PregnanciesController do
  integrate_views

  before do
    controller.stub!(:current_user).and_return(stub_model User)
  end

  it "should display the edit page" do
    pd = Patient.create!(:pregnant => false, :name => 'mary', :user_id => 1)

    get :edit, :patient_id => pd.id.to_s

    assigns[:patient].should == pd
    response.should render_template("pregnancies/edit")
    response.layout.should be_nil
  end

  it "should update patients with pregnancy on" do
    pd = Patient.create!(:pregnant => false, :name => 'mary', :user_id => 1)

    put :update, :patient_id => pd.id.to_s, :pregnant => 'on'

    pd.reload
    pd.pregnant.should == true
  end

  it "should update patients with pregnancy off" do
    pd = Patient.create!(:pregnant => true, :name => 'mary', :user_id => 1)

    put :update, :patient_id => pd.id.to_s

    pd.reload
    pd.pregnant.should == false
  end

  it "should update pregnant patient with pregnancy nil" do
    pd = Patient.create!(:pregnant => true, :name => 'mary', :user_id => 1)

    delete :destroy, :patient_id => pd.id.to_s

    pd.reload
    pd.pregnant.should be_nil
  end

  it "should update non-pregnant patient with pregnancy nil" do
    pending "SF ticket 2783842"

    pd = Patient.create!(:pregnant => false, :name => 'mary', :user_id => 1)

    delete :destroy, :patient_id => pd.id.to_s

    pd.reload
    pd.pregnant.should be_nil
  end

end
