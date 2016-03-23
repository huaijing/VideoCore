
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
    //        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_BGR, GL_UNSIGNED_BYTE, data);
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
               varying vec2   vCoord;
               uniform mat4   uMat;
               void main(void) {
                gl_Position = uMat * vec4(aPos,0.,1.);
                vCoord = aCoord;
               }
        )
        
        return nullptr;
    }
    
    const char * const
    BasicVideoFilterBGRA::pixelKernel() const
    {
        
         KERNEL(GL_ES2_3, m_language,
               precision mediump float;
               varying vec2      vCoord;
               uniform sampler2D uTex0;
               uniform sampler2D uTex1;
               uniform sampler2D uTex2;

               void main(void) {
                   vec4 color_0 = texture2D(uTex0, vCoord);
                   vec4 color_1 = texture2D(uTex1, vCoord);
                   vec4 color_2 = texture2D(uTex2, vCoord);

                   gl_FragData[0] = mix(color_0, color_2, 0.5);
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
                
                NSString *imagePath1 = [mainBundle pathForResource:@"contrast_map" ofType:@"bmp"];
                m_texture = loadBMP_custom(imagePath1.cString);
                glActiveTexture(GL_TEXTURE1);
                glBindTexture(GL_TEXTURE_2D, m_texture);
                
                NSString *imagePath2 = [mainBundle pathForResource:@"11" ofType:@"bmp"];
                m_texture2 = loadBMP_custom(imagePath2.cString);
                glActiveTexture(GL_TEXTURE2);
                glBindTexture(GL_TEXTURE_2D, m_texture2);
                
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
                    int unitex1 = glGetUniformLocation(m_program, "uTex1");
                    glUniform1i(unitex1, 1);
                    
                    
                    glActiveTexture(GL_TEXTURE2);
                    glBindTexture(GL_TEXTURE_2D, m_texture2);
                    int unitex2 = glGetUniformLocation(m_program, "uTex2");
                    glUniform1i(unitex2, 2);
                    
                }
                glUniformMatrix4fv(m_uMatrix, 1, GL_FALSE, &m_matrix[0][0]);
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
