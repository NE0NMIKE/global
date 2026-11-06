/// SceneKit Metal shader modifiers.
///
/// All lighting is done here rather than with SceneKit lights, so every style
/// shares one model: `sunDir` is a view-space direction towards the light.
/// With the day/night overlay off it is a fixed key light from the upper
/// left; with it on, it is the real sun direction.
enum Shaders {
    /// Photo-real Earth: day texture in `diffuse`, city lights in `emission`,
    /// ocean mask in `specular`.
    static let photoEarth = """
    #pragma arguments
    float3 sunDir;
    float dayNight;
    float3 rimColor;
    float rimStrength;
    #pragma body
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float3 l = normalize(sunDir);
    float ndl = dot(n, l);

    // Soft wrap lighting so the lit hemisphere has form without going flat.
    float shade = clamp(ndl * 0.65 + 0.5, 0.0, 1.1);
    float3 dayLit = _surface.diffuse.rgb * shade;

    // Night side: city lights plus a hint of the surface.
    float day = mix(1.0, smoothstep(-0.12, 0.18, ndl), dayNight);
    float3 night = _surface.emission.rgb * 1.5 + _surface.diffuse.rgb * 0.03;
    float3 col = mix(night, dayLit, day);

    // Sun glint on water.
    float3 h = normalize(l + v);
    float spec = pow(max(dot(n, h), 0.0), 48.0) * _surface.specular.r * 0.35 * day;
    col += spec * float3(1.0, 0.95, 0.85);

    // Atmospheric scattering at the limb.
    float rim = pow(1.0 - max(dot(n, v), 0.0), 2.6);
    col = mix(col, rimColor * mix(0.25, 1.0, day), rim * rimStrength);

    _output.color = float4(col, 1.0);
    """

    /// Flat sphere for illustrated styles. `diffuse` holds a land mask when
    /// `useMask` is 1 (silhouette style), otherwise it is unused.
    static let flatSphere = """
    #pragma arguments
    float3 sunDir;
    float3 oceanColor;
    float3 landColor;
    float3 nightColor;
    float nightStrength;
    float useMask;
    float dayNight;
    #pragma body
    float3 n = normalize(_surface.normal);
    float ndl = dot(n, normalize(sunDir));
    float landAmt = useMask * smoothstep(0.35, 0.65, _surface.diffuse.r);
    float3 col = mix(oceanColor, landColor, landAmt);
    // Terminator: crisper when showing the real sun, softer as a key light.
    float edge0 = mix(-0.30, -0.08, dayNight);
    float edge1 = mix(0.40, 0.12, dayNight);
    float nightAmt = (1.0 - smoothstep(edge0, edge1, ndl)) * nightStrength;
    col = mix(col, nightColor, nightAmt);
    _output.color = float4(col, 1.0);
    """

    /// Shading for linework and dots drawn on the sphere: dims towards the
    /// night colour on the far side of the terminator.
    static let inkShade = """
    #pragma arguments
    float3 sunDir;
    float3 nightColor;
    float nightStrength;
    float dayNight;
    #pragma body
    float ndl = dot(normalize(_surface.normal), normalize(sunDir));
    float edge0 = mix(-0.30, -0.08, dayNight);
    float edge1 = mix(0.40, 0.12, dayNight);
    float nightAmt = (1.0 - smoothstep(edge0, edge1, ndl)) * nightStrength * 0.9;
    _output.color.rgb = mix(_output.color.rgb, nightColor * _output.color.a, nightAmt);
    """

    /// Glowing arc: a colour gradient along `u` with two light pulses
    /// travelling in opposite directions. Rendered additively.
    static let arcGlow = """
    #pragma arguments
    float pulsePeriod;
    float baseLevel;
    #pragma body
    float u = _surface.diffuseTexcoord.x;
    float t = fract(scn_frame.time / pulsePeriod);
    float p1 = exp(-pow((u - t) * 9.0, 2.0));
    float p2 = exp(-pow((u - (1.0 - fract(t + 0.5))) * 9.0, 2.0));
    float pulse = max(p1, p2);
    float ends = smoothstep(0.0, 0.03, u) * smoothstep(1.0, 0.97, u);
    float k = (baseLevel + 1.1 * pulse) * ends;
    _output.color = float4(_surface.diffuse.rgb * k + pulse * 0.25 * ends, k);
    """
}
