import MCP

extension Tool.Annotations {
    /// Tool only reads data; does not modify anything.
    public static let readOnly = Tool.Annotations(
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: false,
    )

    /// Tool creates or modifies state but is not destructive (e.g. build, set, add).
    public static let mutation = Tool.Annotations(
        readOnlyHint: false,
        destructiveHint: false,
        openWorldHint: false,
    )

    /// Tool may destroy data or terminate processes (e.g. clean, remove, stop, erase).
    public static let destructive = Tool.Annotations(
        readOnlyHint: false,
        destructiveHint: true,
        openWorldHint: false,
    )
}
