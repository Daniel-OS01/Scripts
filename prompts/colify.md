
Develop a centralized script distribution system with a main orchestrator script (main.sh) that provides access to 10-30 complex automation scripts for Oracle Cloud VPS management, focusing on Docker containerization and Coolify platform operations, with secure GitHub repository secrets integration.

## GITHUB ENVIRONMENT VARIABLES ARCHITECTURE
- **Variable Format:** All environment variables within scripts must use the template format: `{{VARIABLE_NAME}}`
- **Examples:** `{{DEFAULT_SL_OCI}}`, `{{DOCKER_REGISTRY_TOKEN}}`, `{{COOLIFY_API_KEY}}`
- **Security Model:** Scripts must fetch environment variables from GitHub repository secrets during execution
- **Implementation:** Create a secure variable substitution mechanism that replaces template variables with actual values from GitHub secrets
- **Validation:** Include checks to ensure all required environment variables are available before script execution

## PLATFORM SPECIFICATIONS
- **Target Environment:** Oracle Cloud Infrastructure (OCI) instances
- **Operating System:** Ubuntu/Oracle Linux compatibility
- **Container Runtime:** Docker with Coolify integration
- **Execution Method:** `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Daniel-OS01/scripts/refs/heads/main/main.sh)"`
- **Security:** GitHub repository secrets integration with template variable substitution

## SCRIPT COMPLEXITY REQUIREMENTS
All scripts must match the sophistication level of the existing Docker-Cleanup-Management.sh, including:
- **Multi-step automation processes** with conditional logic and GitHub secrets integration
- **System-wide configuration changes** with rollback capabilities and secure credential handling
- **Advanced Docker operations** using secured registry credentials from `{{DOCKER_REGISTRY_TOKEN}}`
- **Coolify integration** using `{{COOLIFY_API_KEY}}` for basic deployment and management operations
- **Oracle Cloud-specific optimizations** using `{{DEFAULT_SL_OCI}}` and other OCI credentials

## TECHNICAL ARCHITECTURE

### 1. Main Script (main.sh)
- **Interface:** Simple text-based menu system with numbered options
- **Security:** Basic user confirmation (y/n prompts) + GitHub secrets validation
- **Environment Variables:** Secure template substitution system that:
  - Fetches variables from GitHub repository secrets
  - Replaces `{{VARIABLE_NAME}}` templates with actual values
  - Validates all required secrets are available
  - Provides clear error messages for missing secrets
- **Oracle Cloud Integration:** Utilize OCI credentials from `{{DEFAULT_SL_OCI}}` and instance metadata

### 2. GitHub Secrets Integration Framework
Create a secure variable management system that:
- **Fetches Secrets:** Retrieves environment variables from GitHub repository secrets during script execution
- **Template Processing:** Scans scripts for `{{VARIABLE_NAME}}` patterns and replaces with actual values
- **Security Validation:** Ensures secrets are not logged or exposed in verbose output
- **Error Handling:** Provides clear feedback when required secrets are missing or invalid
- **Common Variables:** Support for standard variables like:
  - `{{DEFAULT_SL_OCI}}` - Oracle Cloud credentials
  - `{{DOCKER_REGISTRY_TOKEN}}` - Docker registry authentication
  - `{{COOLIFY_API_KEY}}` - Coolify platform access
  - `{{BACKUP_STORAGE_KEY}}` - Backup storage credentials
  - `{{MONITORING_WEBHOOK}}` - Alert notification endpoints

### 3. Script Organization Structure
```
/scripts/
├── oracle/        # OCI-specific utilities using {{DEFAULT_SL_OCI}}
├── docker/     # Complex Docker automation with {{DOCKER_REGISTRY_TOKEN}}
├── coolify/  # Coolify deployment and degugging using {{COOLIFY_API_KEY}}
├── network/  # Advanced networking with secure credentials
├── security/ # Automated security checks with
├── backup/     # Backup automation 
└── maintenance-optimization/ # System maintenance with secure configurations
```

### 4. Individual Script Standards
- **Header Requirements:** Each script must include:
  - Direct curl execution command
  - Required GitHub secrets documentation (e.g., "Requires: {{DEFAULT_SL_OCI}}, {{DOCKER_REGISTRY_TOKEN}}")
  - Oracle Cloud compatibility notes
  - Template variable usage examples
- **Security Implementation:** 
  - All sensitive data referenced as `{{VARIABLE_NAME}}`
  - No hardcoded credentials or tokens
  - Secure variable substitution before execution
  - Validation of required secrets availability
- **Verbose Output:** Detailed progress indicators while protecting sensitive information from logs

## REQUIRED DELIVERABLES

### Phase 1: GitHub Secrets Architecture
1. **Environment Variable Schema:** Define comprehensive list of required GitHub secrets:
   - Oracle Cloud credentials and configurations
   - Docker registry and container management tokens
   - Coolify API keys and endpoints
   - Backup and storage access credentials
   - Monitoring and alerting webhook URLs
   - Security and compliance tokens

2. **Template Processing System:** Create secure variable substitution mechanism:
   - Pattern recognition for `{{VARIABLE_NAME}}` templates
   - GitHub secrets API integration
   - Secure variable replacement without exposure
   - Validation and error handling for missing secrets

### Phase 2: Complex Automation Scripts (10-30 scripts)
1. **Oracle Cloud Optimization Scripts:** Using `{{DEFAULT_SL_OCI}}` for:
   - Network configuration and security hardening

2. **Advanced Docker Automation:** Using `{{DOCKER_REGISTRY_TOKEN}}` for:
   - Registry management and image optimization
   - Security scanning and compliance automation
   - Network diagnosis and troubleshooting
   - Advanced container management and scaling
   - Container health monitoring and alerts
   - Container logs and performance analysis
   - Container security and compliance auditing
   
3. **Coolify Integration Scripts:** Using `{{COOLIFY_API_KEY}}` for:
   - Application deployment and configuration
   - Basic monitoring and health checks
   - Environment management and updates

### Phase 3: Security and Validation Framework
1. **Secrets Management:** Implement:
   - Secure GitHub secrets retrieval
   - Template variable validation
   - Error handling for missing or invalid secrets
   - Audit logging without credential exposure

2. **Quality Assurance:** Include:
   - Script functionality testing with mock secrets
   - Security vulnerability assessment
   - Template variable coverage validation
   - Documentation completeness verification

## SUCCESS CRITERIA
- All scripts executable via single curl command with GitHub secrets integration
- Secure `{{VARIABLE_NAME}}` template system for all sensitive data
- Complex automation matching existing script sophistication
- Simple text-based interface with comprehensive error handling
- No hardcoded credentials - all sensitive data from GitHub repository secrets
- Clear documentation of required GitHub secrets for each script

## SECURITY CONSTRAINTS
- Zero hardcoded credentials in any script
- All sensitive data must use `{{VARIABLE_NAME}}` template format
- GitHub repository secrets must be validated before script execution
- Sensitive information must not appear in logs or verbose output
- Template processing must be secure and not expose secrets during substitution
