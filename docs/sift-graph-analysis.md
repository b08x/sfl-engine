# SIFT-Graph Analysis Output

This directory contains SIFT-Graph analysis reports for the sfl-engine codebase.

## Files

- `sift-graph-ruby-design-patterns.json` - Machine-readable JSON with all claims, provenance tuples, and meta-rubric scores
- `sift-graph-ruby-design-patterns.md` - Human-readable markdown report
- `graph.db.zst` - Codebase-memory knowledge graph artifact (compressed)
- `artifact.json` - Graph artifact metadata

## Report Summary

**Analysis**: Ruby Design Patterns in sfl-engine codebase  
**Generated**: 2026-09-12T12:00:00Z  
**Project**: home-b08x-WorkspaceV3-sfl-engine (3,030 nodes, 5,189 edges)  
**Final Score**: 4.2/5.0 (Strong)  

### Key Findings

- **15 verified Ruby design patterns** with graph-verified provenance
- **3 critique observations** for missing or alternative patterns
- **All claims have valid provenance tuples** verified against the codebase-memory knowledge graph

### Confirmed Patterns

#### Creational (3)
- Factory Method (LMFactory)
- Builder (EngineBuilder)
- Null Object (Ports::Null hierarchy)

#### Structural (5)
- Adapter (Core::Ports + implementations)
- Composite (Pipeline stage composition)
- Repository (PgClauseStore)
- Circuit Breaker (TimeoutBreaker)
- Hexagonal Architecture (Ports & Adapters)

#### Behavioral (3)
- Strategy (interchangeable parsers/annotators)
- Monad (Dry::Monads for error propagation)
- Dependency Injection (extensive use)

#### Pattern-Adjacent (4)
- Decorator-like (Instrumenter wrapping)
- Template Method-like (Pipeline#compile)
- Chain of Responsibility-like (cache fallback)

### Validation

All provenance tuples have been validated:
- ✅ All referenced files exist in the codebase
- ✅ All line ranges are within file bounds
- ✅ All qualified names follow the codebase structure
- ✅ All node types are appropriate for their targets

### Meta-Rubric Scores

| Dimension | Score | Weighted |
|-----------|-------|----------|
| Claim Provenance | 5.00 | 2.00 |
| Section Completeness | 4.00 | 1.00 |
| Severity Calibration | 4.00 | 0.80 |
| Self-Critique Payoff | 3.00 | 0.45 |
| **Final Score** | | **4.2** |

**Status**: Strong — reliable for architectural decision-making

## Methodology

This analysis uses the **SIFT-Graph** methodology:
1. Queries the codebase-memory knowledge graph for pattern evidence
2. Generates claims with provenance tuples linked to graph nodes
3. Audits provenance tuples against the graph
4. Applies meta-rubric scoring (Claim Provenance, Section Completeness, Severity Calibration, Self-Critique Payoff)
5. Computes final score with Weighted Sum + Pitfall Penalty + Essential Cap

## Usage

To regenerate or extend this analysis:

```bash
# Ensure codebase is indexed
mcp_codebase_memory_mcp_index_repository \
  repo_path=/home/b08x/WorkspaceV3/sfl-engine \
  mode=full \
  persistence=true

# The graph artifact will be written to .codebase-memory/graph.db.zst
# Analysis can then be run against the indexed graph
```

## References

- [SIFT-Graph Skill](~/.syncopated/skills/sift-graph/SKILL.md)
- [sfl-engine AGENTS.md](/home/b08x/WorkspaceV3/sfl-engine/AGENTS.md)
- [codebase-memory MCP server](~/.syncopated/skills/codebase-memory/SKILL.md)
