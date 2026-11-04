SCHEMA_DIR ?= ../SiennaSchemas
JULIA_SCHEMAS = julia --project=scripts/outputs_schema -e

# Needs SCHEMA_DIR (default ../SiennaSchemas) checked out.
outputs-schemas-sync:
	SCHEMA_DIR=$(abspath $(SCHEMA_DIR)) $(JULIA_SCHEMAS) 'using Pkg; Pkg.instantiate(); include("scripts/outputs_schema/sync_quantity_kinds.jl")'

outputs-schemas-generate:
	$(JULIA_SCHEMAS) 'using Pkg; Pkg.instantiate(); include("scripts/outputs_schema/generate_outputs_models.jl")'

outputs-schemas: outputs-schemas-sync outputs-schemas-generate

outputs-schemas-check:
	scratch=$$(mktemp -d) && \
	OUTPUTS_SCHEMAS_OUT=$$scratch $(JULIA_SCHEMAS) 'using Pkg; Pkg.instantiate(); include("scripts/outputs_schema/generate_outputs_models.jl")' && \
	diff -r $$scratch/src PowerOutputSchemas.jl/src; rc=$$?; rm -rf $$scratch; exit $$rc

.PHONY: outputs-schemas-sync outputs-schemas-generate outputs-schemas outputs-schemas-check
