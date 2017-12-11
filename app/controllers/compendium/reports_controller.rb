module Compendium
  class ReportsController < ::ApplicationController
    helper Compendium::ReportsHelper
    include Compendium::ReportsHelper

    before_action :find_report
    before_action :find_query
    before_action :validate_options, only: %i[run export]
    before_action :run_report, only: %i[run export]

    def setup
      render_setup
    end

    def run
      respond_to do |format|
        format.json do
          render json: @query ? @query.results : @report.results
        end

        format.any do
          template = template_exists?(@prefix, get_template_prefixes) ? @prefix : 'run'
          render action: template, locals: { report: @report }
        end
      end
    end

    def export
      unless @report.exports?(request.format)
        redirect_to action: :setup, format: nil
        return
      end

      respond_to do |format|
        format.csv do
          filename = @report.report_name.to_s.parameterize + '-' + Time.current.strftime('%Y%m%d%H%I%S')
          response.headers['Content-Disposition'] = 'attachment; filename="' + filename + '.csv"'

          query = @report.queries[@report.exporters[:csv]]
          render text: query.render_csv
        end

        format.any do
          redirect_to action: :setup, format: nil
        end
      end
    end

    private

    def find_report
      @prefix = params[:report_name]
      @report_name = "#{@prefix}_report"

      begin
        require(@report_name) unless Rails.env.development? || Module.const_defined?(@report_name.classify)
        @report_class = @report_name.camelize.constantize
        @report = setup_report
      rescue LoadError
        flash[:error] = t(:invalid_report, scope: 'compendium.reports')
        redirect_to action: :index
      end
    end

    def find_query
      return unless params[:query]
      @query = @report.queries[params[:query]]

      unless @query
        flash[:error] = t(:invalid_report_query, scope: 'compendium.reports')
        redirect_to action: :setup, report_name: params[:report_name]
      end
    end

    def render_setup(opts = {})
      locals = { report: @report, prefix: @prefix }
      opts.empty? ? render(action: :setup, locals: locals) : render_if_exists(opts.merge(locals: locals)) || render(action: :setup, locals: locals)
    end

    def setup_report
      @report_class.new(params[:report] || {})
    end

    def validate_options
      render_setup && return unless @report.valid?
    end

    def run_report
      @report.run(self, @query ? { only: @query.name } : {})
    end

    def get_template_prefixes
      paths = []
      klass = self.class

      begin
        paths << klass.name.underscore.gsub(/_controller$/, '')
        klass = klass.superclass
      end while(klass != ActionController::Base)

      paths
    end
  end
end
