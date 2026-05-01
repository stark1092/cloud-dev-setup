import logging

from .config import Config, load_nodes_toml, load_sources_toml

logger = logging.getLogger("dashboard.reload")


def reload_config(cfg: Config) -> tuple[int, int]:
    """Re-read sources.toml and nodes.toml in place. Returns (n_sources, n_nodes)."""
    if cfg.sources_toml_path is not None:
        cfg.sources = load_sources_toml(cfg.sources_toml_path)
    if cfg.nodes_toml_path is not None:
        cfg.nodes = load_nodes_toml(cfg.nodes_toml_path)
    logger.info("reload: %d sources, %d nodes", len(cfg.sources), len(cfg.nodes))
    return len(cfg.sources), len(cfg.nodes)
