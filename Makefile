SCHEMA_DIR ?= ../SiennaSchemas
JULIA_SCHEMAS = julia --project=scripts/outputs_schema -e

# Needs SCHEMA_DIR (default ../SiennaSchemas) checked out.
outputs-schemas-sync:
	SCHEMA_DIR=$(abspath $(SCHEMA_DIR)) $(JULIA_SCHEMAS) 'using Pkg; Pkg.instantiate(); include("scripts/outputs_schema/sync_quantity_kinds.jl")'

outputs-schemas-generate:
	$(JULIA_SCHEMAS) 'using Pkg; Pkg.instantiate(); include("scripts/outputs_schema/generate_outputs_models.jl")'

outputs-schemas: outputs-schemas-sync outputs-schemas-generate

# Runs sync and generate in a scratch copy, then diffs the schemas and src against the checkout.
# A missing SCHEMA_DIR is an error.
outputs-schemas-check:
	test -f $(SCHEMA_DIR)/Core/units.json || { echo "SiennaSchemas not found at $(SCHEMA_DIR)"; exit 1; }
	scratch=$$(mktemp -d) && \
	mkdir $$scratch/repo && \
	cp -R schemas scripts $$scratch/repo/ && \
	mkdir $$scratch/PowerOutputSchemas.jl && \
	(cd $$scratch/repo && \
	SCHEMA_DIR=$(abspath $(SCHEMA_DIR)) OUTPUTS_SCHEMAS_OUT=$$scratch/PowerOutputSchemas.jl \
	julia --project=scripts/outputs_schema -e 'using Pkg; Pkg.instantiate(); include("scripts/outputs_schema/sync_quantity_kinds.jl"); include("scripts/outputs_schema/generate_outputs_models.jl")') && \
	diff -r $$scratch/repo/schemas/outputs schemas/outputs && \
	diff -r $$scratch/PowerOutputSchemas.jl/src PowerOutputSchemas.jl/src; rc=$$?; rm -rf $$scratch; exit $$rc

.PHONY: outputs-schemas-sync outputs-schemas-generate outputs-schemas outputs-schemas-check
