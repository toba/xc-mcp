import XcodeProj

/// Reads and writes the package build-tool plugin links of a target
///
/// Xcode records a plugin (Build Phases > Run Build Tool Plug-ins) as a `PBXTargetDependency`
/// whose `productRef` names `plugin:<name>`. The plugin stays out of `packageProductDependencies`
/// and out of every build phase. XcodeProj strips the `plugin:` prefix on read and keeps its
/// `isPlugin` flag internal. A plugin link therefore shows only as a product target dependency
/// that the target does not also list as a package product.
enum PackagePluginLinks {
    static let prefix = "plugin:"

    /// The product name without a leading `plugin:` prefix.
    static func bareName(_ name: String) -> String {
        name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    /// The target dependencies that link a package plugin to `target`.
    static func dependencies(of target: PBXNativeTarget) -> [PBXTargetDependency] {
        let linked = target.packageProductDependencies ?? []
        return target.dependencies.filter { dependency in
            guard let product = dependency.product else { return false }
            return !linked.contains { $0 === product }
        }
    }

    /// The plugin link on `target` for the product `name`, bare or `plugin:`-prefixed.
    static func dependency(named name: String, of target: PBXNativeTarget) -> PBXTargetDependency? {
        let bare = bareName(name)
        return dependencies(of: target).first { $0.product?.productName == bare }
    }

    /// Links the plugin `name` to `target` the way Xcode writes it.
    ///
    /// - Returns: The product dependency that the new target dependency references.
    @discardableResult
    static func link(
        _ name: String,
        package: XCRemoteSwiftPackageReference?,
        to target: PBXNativeTarget,
        in pbxproj: PBXProj,
    ) -> XCSwiftPackageProductDependency {
        let product = XCSwiftPackageProductDependency(
            productName: bareName(name), package: package, isPlugin: true,
        )
        pbxproj.add(object: product)

        let dependency = PBXTargetDependency(product: product)
        pbxproj.add(object: dependency)
        target.dependencies.append(dependency)
        return product
    }
}
