//! Provider metadata and capability definitions.

const std = @import("std");

/// Features a provider can expose.
pub const Capability = enum { completion, chat, agent };

/// Key providers supported by the Phase 2 auth plan.
pub const Kind = enum {
    openai,
    anthropic,
    xai,
    azure_openai,
    github_copilot,
};

/// Describes the static properties of a provider.
pub const Descriptor = struct {
    kind: Kind,
    slug: []const u8,
    display_name: []const u8,
    config_key: []const u8,
    default_capabilities: []const Capability,
    default_models: []const []const u8,
    variants: []const []const u8 = &[_][]const u8{},

    pub fn supports(self: Descriptor, capability: Capability) bool {
        return std.mem.indexOfScalar(Capability, self.default_capabilities, capability) != null;
    }
};

const caps_completion_chat = [_]Capability{ .completion, .chat };
const caps_completion_chat_agent = [_]Capability{ .completion, .chat, .agent };

const openai_models = [_][]const u8{
    "gpt-4.1-mini",
    "gpt-4.1",
    "gpt-4.1-preview",
};

const anthropic_models = [_][]const u8{
    "claude-3.5-sonnet",
    "claude-4.1-sonnet",
    "claude-4.1-haiku",
};

const xai_models = [_][]const u8{
    "grok-2",
    "grok-2-mini",
};

const azure_models = [_][]const u8{
    "gpt-4o",
    "gpt-4o-mini",
};

const copilot_models = [_][]const u8{
    "copilot-gpt-4.1",
    "copilot-gpt-4o",
};

const copilot_variants = [_][]const u8{
    "copilot",
    "copilot[grok]",
    "copilot[claude]",
    "copilot[gpt-5-codex]",
};

const descriptor_table = [_]Descriptor{
    .{
        .kind = .openai,
        .slug = "openai",
        .display_name = "OpenAI",
        .config_key = "providers.openai",
        .default_capabilities = &caps_completion_chat,
        .default_models = &openai_models,
    },
    .{
        .kind = .anthropic,
        .slug = "anthropic",
        .display_name = "Anthropic Claude",
        .config_key = "providers.anthropic",
        .default_capabilities = &caps_completion_chat,
        .default_models = &anthropic_models,
    },
    .{
        .kind = .xai,
        .slug = "xai",
        .display_name = "xAI Grok",
        .config_key = "providers.xai",
        .default_capabilities = &caps_completion_chat,
        .default_models = &xai_models,
    },
    .{
        .kind = .azure_openai,
        .slug = "azure-openai",
        .display_name = "Azure OpenAI",
        .config_key = "providers.azure_openai",
        .default_capabilities = &caps_completion_chat,
        .default_models = &azure_models,
    },
    .{
        .kind = .github_copilot,
        .slug = "github-copilot",
        .display_name = "GitHub Copilot",
        .config_key = "providers.github_copilot",
        .default_capabilities = &caps_completion_chat_agent,
        .default_models = &copilot_models,
        .variants = &copilot_variants,
    },
};

pub fn descriptors() []const Descriptor {
    return &descriptor_table;
}

pub fn descriptor(kind: Kind) *const Descriptor {
    for (descriptor_table) |desc| {
        if (desc.kind == kind) return &desc;
    }
    unreachable; // exhaustive enum coverage above
}

pub fn slug(kind: Kind) []const u8 {
    return descriptor(kind).slug;
}

pub fn configKey(kind: Kind) []const u8 {
    return descriptor(kind).config_key;
}

pub fn supports(kind: Kind, capability: Capability) bool {
    return descriptor(kind).supports(capability);
}

pub fn defaultModels(kind: Kind) []const []const u8 {
    return descriptor(kind).default_models;
}

pub fn defaultCapabilities(kind: Kind) []const Capability {
    return descriptor(kind).default_capabilities;
}

pub fn variants(kind: Kind) []const []const u8 {
    return descriptor(kind).variants;
}

test "descriptor lookup covers all kinds" {
    for (descriptor_table) |desc| {
        const round = descriptor(desc.kind);
        try std.testing.expect(std.mem.eql(u8, desc.slug, round.slug));
    }
}
