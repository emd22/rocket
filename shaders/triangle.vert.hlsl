// cbuffer UniformBlock : register(b0, space1) {
//     float4x4 MVP;
//     float4x4 ModelMatrix;
// };

struct Input {
    uint VertexID : SV_VertexID;
    // float3 Position : POSITION;
    // float3 Normal : NORMAL;
};

struct Output {
    float4 Position : SV_Position;
    // float3 Normal : NORMAL;
    // float3 FragPos : POSITION;
};



float4 main(Input input) {
    // Output output;

    float2 Positions[3] = {
        float2(0.0, -0.5),
        float2(0.5, 0.5),
        float2(-0.5, 0.5)
    };

    return float4(Positions[input.VertexID], 0.0, 1.0);

    // output.Position = mul(MVP, float4(input.Position, 1.0));
    //
    // output.Normal = input.Position;
    // output.FragPos = float3(ModelMatrix * float4(input.Position, 1.0));

    // return output;
}
