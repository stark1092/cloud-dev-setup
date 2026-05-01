import textwrap

from dashboard_server.config import Config, load_nodes_toml, load_sources_toml
from dashboard_server.reload import reload_config


def test_reload_picks_up_new_source(tmp_path):
    sources_path = tmp_path / "sources.toml"
    sources_path.write_text(textwrap.dedent("""
        [sources.s1]
        display_name = "S1"
        token_hash = "h1"
    """).strip())
    cfg = Config(sources_toml_path=sources_path, sources=load_sources_toml(sources_path))
    assert set(cfg.sources) == {"s1"}

    sources_path.write_text(textwrap.dedent("""
        [sources.s1]
        display_name = "S1"
        token_hash = "h1"

        [sources.s2]
        display_name = "S2"
        token_hash = "h2"
    """).strip())

    n_sources, n_nodes = reload_config(cfg)
    assert n_sources == 2
    assert n_nodes == 0
    assert set(cfg.sources) == {"s1", "s2"}
    assert cfg.sources["s2"].display_name == "S2"


def test_reload_picks_up_new_node(tmp_path):
    nodes_path = tmp_path / "nodes.toml"
    nodes_path.write_text(textwrap.dedent("""
        [nodes.alpha]
        label = "Alpha"
        tailscale_name = "alpha"
        method = "icmp"
    """).strip())
    cfg = Config(nodes_toml_path=nodes_path, nodes=load_nodes_toml(nodes_path))
    assert set(cfg.nodes) == {"alpha"}

    nodes_path.write_text(textwrap.dedent("""
        [nodes.alpha]
        label = "Alpha"
        tailscale_name = "alpha"
        method = "icmp"

        [nodes.beta]
        label = "Beta"
        tailscale_name = "beta"
        method = "tcp"
        tcp_port = 2222
    """).strip())

    n_sources, n_nodes = reload_config(cfg)
    assert n_nodes == 2
    assert cfg.nodes["beta"].method == "tcp"
    assert cfg.nodes["beta"].tcp_port == 2222


def test_reload_drops_removed_source(tmp_path):
    sources_path = tmp_path / "sources.toml"
    sources_path.write_text("[sources.s1]\ndisplay_name = \"S1\"\ntoken_hash = \"h1\"\n")
    cfg = Config(sources_toml_path=sources_path, sources=load_sources_toml(sources_path))
    sources_path.write_text("")  # empty
    reload_config(cfg)
    assert cfg.sources == {}


def test_load_nodes_rejects_invalid_method(tmp_path):
    p = tmp_path / "nodes.toml"
    p.write_text("[nodes.x]\nlabel='x'\ntailscale_name='x'\nmethod='garbage'\n")
    try:
        load_nodes_toml(p)
    except ValueError as e:
        assert "garbage" in str(e)
    else:
        raise AssertionError("expected ValueError")
