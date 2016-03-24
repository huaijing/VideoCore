
#include <videocore/filters/Basic/BasicVideoFilterBGRA.h>

#include <TargetConditionals.h>


#ifdef TARGET_OS_IPHONE

#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES3/gl.h>
#include <videocore/sources/iOS/GLESUtil.h>
#include <videocore/filters/FilterFactory.h>

#endif

static GLuint loadBMP_custom(const char *imagepath)
{
    // Data read from the header of the BMP file
    unsigned char header[54]; // Each BMP file begins by a 54-bytes header
    unsigned int dataPos;     // Position in the file where the actual data begins
    unsigned int width, height;
    unsigned int imageSize;   // = width*height*3
    // Actual RGB data
    unsigned char * data;
    
    //Open the file
    FILE *file = fopen(imagepath, "rb");
    if (!file) {
        printf("Image could not be opened");
        return 0;
    }
    
    if ( fread(header, 1, 54, file)!=54 ){ // If not 54 bytes read : problem
        printf("Not a correct BMP file");
        return false;
    }
    
    if ( header[0]!='B' || header[1]!='M' ){
        printf("Not a correct BMP file");
        return 0;
    }
    
    // Read ints from the byte array
    dataPos    = *(int*)&(header[0x0A]);
    imageSize  = *(int*)&(header[0x22]);
    width      = *(int*)&(header[0x12]);
    height     = *(int*)&(header[0x16]);
    
    // Some BMP files are misformatted, guess missing information
    if (imageSize == 0)    imageSize = width*height*3; // 3 : one byte for each Red, Green and Blue component
    if (dataPos == 0)      dataPos = 54; // The BMP header is done that way
    
    // Create a buffer
    data = new unsigned char [imageSize];
    
    // Read the actual data from the file into the buffer
    fread(data,1,imageSize,file);
    
    // Create one OpenGL texture
    GLuint textureID;
    glGenTextures(1, &textureID);
    
    // "Bind" the newly created texture : all future texture functions will modify this texture
    glBindTexture(GL_TEXTURE_2D, textureID);
    
    // Give the image to OpenGL
//            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_BGR, GL_UNSIGNED_BYTE, data);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, data);
    
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    
    //Everything is in memory now, the file can be closed
    fclose(file);
    delete []data;
    
    return textureID;
}

namespace videocore { namespace filters {
 
    bool BasicVideoFilterBGRA::s_registered = BasicVideoFilterBGRA::registerFilter();
    
    bool
    BasicVideoFilterBGRA::registerFilter()
    {
        FilterFactory::_register("com.videocore.filters.bgra", []() { return new BasicVideoFilterBGRA(); });
        return true;
    }
    
    BasicVideoFilterBGRA::BasicVideoFilterBGRA()
    : IVideoFilter(), m_initialized(false), m_bound(false)
    {
        
    }
    BasicVideoFilterBGRA::~BasicVideoFilterBGRA()
    {
        glDeleteProgram(m_program);
        glDeleteVertexArraysOES(1, &m_vao);
        
    }
    
    const char * const
    BasicVideoFilterBGRA::vertexKernel() const
    {
        
        KERNEL(GL_ES2_3, m_language,
               attribute vec2 aPos;
               attribute vec2 aCoord;
               varying vec2   textureCoordinate;
               uniform mat4   uMat;
               void main(void) {
                gl_Position = uMat * vec4(aPos,0.,1.);
                textureCoordinate = aCoord;
               }
        )
        
        return nullptr;
    }
    
    const char * const
    BasicVideoFilterBGRA::pixelKernel() const
    {
        
         KERNEL(GL_ES2_3, m_language,
               precision highp float;
               varying vec2      textureCoordinate;
               uniform sampler2D inputImageTexture;
               uniform sampler2D inputImageTexture2;  //aden_map_2
//               uniform sampler2D inputImageTexture3;
                
               uniform float     uTime;
                
               const float texelWidthOffset = 1.0 / 320.0;
               const float texelHeightOffset = 1.0 / 480.0;
                
               vec2 getZoomPosition(float zoomTimes) {
                   const float EPS = 0.0001;
                   float zoom_x = (textureCoordinate.x - 0.5) / (zoomTimes + EPS);
                   float zoom_y = (textureCoordinate.y - 0.5) / (zoomTimes + EPS);
                
                   return vec2(0.5 + zoom_x, 0.5 + zoom_y);
               }
                
               vec4 getColor(float zoomTimes) {
                    vec2 pos = getZoomPosition(zoomTimes);
                
                    float u = mod(pos.x, texelWidthOffset);
                    float v = mod(pos.y, texelHeightOffset);
                
                    float _x = pos.x - u;
                    float _y = pos.y - v;
                
                    vec4 data_00 = texture2D(inputImageTexture, vec2(_x, _y));
                    vec4 data_01 = texture2D(inputImageTexture, vec2(_x, _y + texelHeightOffset));
                    vec4 data_10 = texture2D(inputImageTexture, vec2(_x + texelWidthOffset, _y));
                    vec4 data_11 = texture2D(inputImageTexture, vec2(_x + texelWidthOffset, _y + texelHeightOffset));
                    
                    return (1.0 - u) * (1.0 - v) * data_00 + (1.0 - u) * v * data_01 + u * (1.0 - v) * data_10 + u * v * data_11;
               }
                
               // 'size' is the number of shades per channel (e.g., 65 for a 65x(65*65) color map)\n
               highp vec4 ig_texture3D(sampler2D tex, highp vec3 texCoord, float size) {
                    float sliceSize = 1.0 / size;
                    float slicePixelSize = sliceSize / size;
                    float sliceInnerSize = slicePixelSize * (size - 1.0);
                    float xOffset = 0.5 * sliceSize + texCoord.x * (1.0 - sliceSize);
                    float yOffset = 0.5 * slicePixelSize + texCoord.y * sliceInnerSize;
                    float zOffset = texCoord.z * (size - 1.0);
                    
                    float zSlice0 = floor(zOffset);
                    float zSlice1 = zSlice0 + 1.0;
                    float s0 = yOffset + (zSlice0 * sliceSize);
                    float s1 = yOffset + (zSlice1 * sliceSize);
//                    highp vec4 slice0Color = texture2D(tex, vec2(xOffset, s0));
//                    highp vec4 slice1Color = texture2D(tex, vec2(xOffset, s1));
                    highp vec4 slice0Color = texture2D(tex, vec2(1.0 - xOffset, s0));
                    highp vec4 slice1Color = texture2D(tex, vec2(1.0 - xOffset, s1));
                   
                    return mix(slice0Color, slice1Color, zOffset - zSlice0);
               }
                
               void main(void) {
                   
                   highp vec4 texel;
                   const float threshold0 = 50.0;
                   const float threshold1 = 100.0;
                   const float threshold2 = 150.0;
                   if(uTime < threshold0) {
                       float verticalThift = uTime / 50.0;
                       float newY = verticalThift + textureCoordinate.y;
                       if (newY <= 1.0) {
                           texel = texture2D(inputImageTexture, vec2(textureCoordinate.x, newY));
                       }
                       else {
                           texel = texture2D(inputImageTexture, vec2(textureCoordinate.x, newY - 1.0));
                       }
                   }
                   else if(uTime < threshold1) {
                       float horizontalThift = (uTime - threshold0) / 50.0;
                       float newX = horizontalThift + textureCoordinate.x;
                       if (newX <= 1.0) {
                           texel = texture2D(inputImageTexture, vec2(newX, textureCoordinate.y));
                       }
                       else
                       {
                           texel = texture2D(inputImageTexture, vec2(newX - 1.0, textureCoordinate.y));
                       }
                   }
                   else if(uTime < threshold2)
                   {
                       float zoomTimes = max(1.0, (uTime - threshold1) / 15.0);
                       texel = getColor(zoomTimes);
                   }
                   else
                   {
                       texel = texture2D(inputImageTexture, textureCoordinate);
                   }

                   highp vec4 inputTexel = texel;
                   texel.rgb = ig_texture3D(inputImageTexture2, texel.rgb, 33.0).rgb;
                   texel.rgb = mix(inputTexel.rgb, texel.rgb, 1.0);
                   
                   gl_FragColor = texel;

               }
        )
        
        return nullptr;
    }
    void
    BasicVideoFilterBGRA::initialize()
    {
        switch(m_language) {
            case GL_ES2_3:
            case GL_2: {
                setProgram(build_program(vertexKernel(), pixelKernel()));
                glGenVertexArraysOES(1, &m_vao);
                glBindVertexArrayOES(m_vao);
                m_uMatrix = glGetUniformLocation(m_program, "uMat");
                int attrpos = glGetAttribLocation(m_program, "aPos");
                int attrtex = glGetAttribLocation(m_program, "aCoord");
                
                glEnableVertexAttribArray(attrpos);
                glEnableVertexAttribArray(attrtex);
                glVertexAttribPointer(attrpos, BUFFER_SIZE_POSITION, GL_FLOAT, GL_FALSE, BUFFER_STRIDE, BUFFER_OFFSET_POSITION);
                glVertexAttribPointer(attrtex, BUFFER_SIZE_POSITION, GL_FLOAT, GL_FALSE, BUFFER_STRIDE, BUFFER_OFFSET_TEXTURE);
                
                NSBundle *mainBundle = [NSBundle mainBundle];
                
                NSString *imagePath1 = [mainBundle pathForResource:@"aden_map_2" ofType:@"bmp"];
                m_texture = loadBMP_custom(imagePath1.cString);
                glActiveTexture(GL_TEXTURE1);
                glBindTexture(GL_TEXTURE_2D, m_texture);
                
//                NSString *imagePath2 = [mainBundle pathForResource:@"11_2" ofType:@"bmp"];
//                m_texture2 = loadBMP_custom(imagePath2.cString);
//                glActiveTexture(GL_TEXTURE2);
//                glBindTexture(GL_TEXTURE_2D, m_texture2);
                
                m_uTime = glGetUniformLocation(m_program, "uTime");

                
                m_initialized = true;
            }
                break;
            case GL_3:
                break;
        }
    }
    void
    BasicVideoFilterBGRA::bind()
    {
        switch(m_language) {
            case GL_ES2_3:
            case GL_2:
            {
                if(!m_bound) {
                    if(!initialized()) {
                        initialize();
                    }
                    
                    glUseProgram(m_program);
                    glBindVertexArrayOES(m_vao);
                    
                    glActiveTexture(GL_TEXTURE1);
                    glBindTexture(GL_TEXTURE_2D, m_texture);
                    int unitex1 = glGetUniformLocation(m_program, "inputImageTexture2");
                    glUniform1i(unitex1, 1);
                    
                    
//                    glActiveTexture(GL_TEXTURE2);
//                    glBindTexture(GL_TEXTURE_2D, m_texture2);
//                    int unitex2 = glGetUniformLocation(m_program, "inputImageTexture3");
//                    glUniform1i(unitex2, 2);
                    
                }
                
                glUniformMatrix4fv(m_uMatrix, 1, GL_FALSE, &m_matrix[0][0]);
                glUniform1f(m_uTime, m_time);

            }
                break;
            case GL_3:
                break;
        }
    }
    void
    BasicVideoFilterBGRA::unbind()
    {
        m_bound = false;
//        GLuint texture = 1;
//        glDeleteTextures(1, &texture);
//        
//        GLuint texture2 = 2;
//        glDeleteTextures(1, &texture2);
    }
}
}
