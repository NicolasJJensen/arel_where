require_relative "lib/arel_where/version"

Gem::Specification.new do |spec|
  spec.name = "arel_where"
  spec.version = AW::VERSION
  spec.authors = ["Nicolas J Jensen"]
  spec.email = ["nicolasjensen9@gmail.com"]
  spec.summary = "Composable Arel predicate chains"
  spec.description = <<~DESCRIPTION
    arel_where keeps the ordinary Active Record hash condition and puts a composable
    predicate on the value side, so User.where(age: AW.gt(18).and(AW.lt(65))) builds the
    Arel node for that column. Chains cover every Arel predication, SQL functions such as
    LOWER and TRIM, and boolean combinators over the same attribute. An opt-in refinement
    drops the AW prefix inside a single lexical scope. Helper blocks can preserve the
    caller's context with AW.build or use a separate receiver with AW.context. Wharel-derived
    Arel blocks support filtering, ordering, selection, grouping, and value extraction.
  DESCRIPTION
  spec.license = "MIT"
  spec.homepage = "https://github.com/NicolasJJensen/arel_where"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "licenses/*.txt", "README.md", "CHANGELOG.md", "LICENSE.txt"]
      .select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]
  spec.add_dependency "activerecord", ">= 7.0", "< 9.0"
end
