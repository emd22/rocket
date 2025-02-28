struct Input {
    float4 Position : SV_Position;

    float3 Normal : NORMAL;
    float3 FragPos : POSITION;
};

float4 main(Input input) : SV_Target0 {
    float3 norm = normalize(input.Normal);
    float3 light_dir = normalize(float3(0, 5, 2) - input.FragPos);

    float diffuse = max(dot(norm, light_dir), 0.0);

    // return float4(diffuse * float3(1.0, 1.0, 1.0), 1.0);
    return float4(input.Normal, 1.0);
}
