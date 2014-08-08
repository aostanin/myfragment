cmake_minimum_required(VERSION 2.6)
project(kinect-framegrabber)

add_executable(kinect-framegrabber kinect-framegrabber.cc)

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Wall")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -Wall")

find_package(libfreenect REQUIRED)
find_package(OpenCV REQUIRED)
include_directories(${FREENECT_INCLUDE_DIRS})
target_link_libraries(kinect-framegrabber ${FREENECT_LIBRARIES} ${OpenCV_LIBS})
