//! Provider interface placeholder.
pub const Provider = struct {
    pub const Capability = enum { completion, chat, agent };

    pub fn name(self: Provider) []const u8 {
        return self._name;
    }

    _name: []const u8,
};
