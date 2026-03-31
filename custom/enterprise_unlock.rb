# Unlock enterprise-tier features in Super Admin
# Sets INSTALLATION_PRICING_PLAN to 'enterprise' so that:
#   - Custom Branding
#   - Agent Capacity
#   - Audit Logs
#   - Disable Branding
# ...are unlocked (no longer show the lock icon).
#
# SAML SSO remains locked — it requires the /app/enterprise directory
# (enterprise source code) which is not included in this image.

Rails.application.config.after_initialize do
  Thread.new do
    retries = 0
    begin
      ActiveRecord::Base.connection_pool.with_connection do
        InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN').tap do |c|
          c.value = 'enterprise'
          c.save! if c.new_record? || c.value_changed?
        end
      end
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
      retries += 1
      sleep 3
      retry if retries < 5
    rescue StandardError => e
      Rails.logger.warn "[EnterpriseUnlock] #{e.message}"
    end
  end
end
