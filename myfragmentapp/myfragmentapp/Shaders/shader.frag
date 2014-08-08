precision mediump float;

uniform vec2 screenSize;
uniform float time;
uniform sampler2D depthTexture;

void main()
{
    vec4 color = vec4(gl_FragCoord.x / screenSize.x, gl_FragCoord.y / screenSize.y, 0.0, 1.0);
    color *= texture2D(depthTexture, vec2(1.0 - gl_FragCoord.x / screenSize.x, 1.0 - gl_FragCoord.y / screenSize.y));
    gl_FragColor = color;
}