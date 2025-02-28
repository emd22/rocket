// TODO: storage buffer
cbuffer UniformBlock : register(b0, space1) {
    float4x4 MVP;
    float4x4 ModelMatrix;
};

struct Input {
    float3 Position : POSITION;
    float3 Normal : NORMAL;
};

struct Output {
    float4 Position : SV_Position;
    float3 Normal : NORMAL;
    float3 FragPos : POSITION;
};

Output main(Input input) {
    Output output;

    output.Position = mul(MVP, float4(input.Position, 1.0));
    // output.Normal = input.Normal;
    output.Normal = input.Position;
    output.FragPos = float3(ModelMatrix * float4(input.Position, 1.0));

    return output;
}
