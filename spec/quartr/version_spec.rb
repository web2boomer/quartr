# frozen_string_literal: true

require "spec_helper"

RSpec.describe Quartr do
  it "has a version number" do
    expect(Quartr::VERSION).not_to be_nil
  end

  it "has a version matching semver format" do
    expect(Quartr::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  describe "error classes" do
    it "defines Error as a subclass of StandardError" do
      expect(Quartr::Error).to be < StandardError
    end

    it "defines AccessDenied as a subclass of Error" do
      expect(Quartr::AccessDenied).to be < Quartr::Error
    end

    it "defines ServiceUnavailable as a subclass of Error" do
      expect(Quartr::ServiceUnavailable).to be < Quartr::Error
    end

    it "defines InvalidResponse as a subclass of Error" do
      expect(Quartr::InvalidResponse).to be < Quartr::Error
    end

    it "defines ServerError as a subclass of Error" do
      expect(Quartr::ServerError).to be < Quartr::Error
    end

    it "defines NotFound as a subclass of Error" do
      expect(Quartr::NotFound).to be < Quartr::Error
    end
  end
end
