classdef MarkerTracking < handle
    % MATLAB class to track markers from video files

    properties
        filename % Raw video filename
        original_frame_rate % Frame rate of the original file
        frames_gray % Grayscale frames 
        inclusion_mask % Regions drawn over the markers that need to be tracked, drawn interactively
        threshold_val % The theshold which the user chooses to make a binary mask
        initial_point_locs % Coordiantes for points to be tracked from the first frame
        tracked_x_log % Array with num_frames*num_points size containing the x coordiantes of tracked marker(s)
        tracked_y_log % Array with num_frames*num_points size containing the y coordiantes of tracked marker(s)
    end
    
    methods (Static)


        function frames_gray = convert_frames_to_gray(frames)
            % Takes in RGB frame stack and converts to grayscale images
            % Input args:
            % frames: 4D stack of images (3-channel RGB images stacked)
            % Outputs:
            % Raw grayscale images

            frames_gray = zeros(size(frames,1),size(frames,2),size(frames,4),"uint8");
            for i = 1:size(frames,4)
                % Other than converting to grayscale, other adjustments on
                % 2D slices can be performed here
                frames_gray(:,:,i) = im2gray(frames(:,:,:,i));
            end
        end


    end

    methods
        function obj = MarkerTracking(filename)
            % MarkerTracking: Construct an instance of this class
            % Input arg
            % filename (string): full file location and name
            obj.filename = filename;
        end

        function read_frames_partial(obj, start_time, end_time)
            % Reads videofile and extracts frames based
            % on the time range given

            % Input args:
            % start_time (double)= beginning time of portion of interest in seconds
            % end_time (double) = end time of portion of interest in seconds

            videoSource = VideoReader(obj.filename);
            fs = videoSource.FrameRate;
            frames = read(videoSource,[round(start_time*fs+1) round(end_time*fs)]);
            obj.frames_gray = obj.convert_frames_to_gray(frames);
        end

        function read_frames_all(obj)
            % Reads videofile and extracts frames

            videoSource = VideoReader(obj.filename);
            fs = videoSource.FrameRate;
            frames = read(videoSource);
            obj.original_frame_rate = fs;
            
            obj.frames_gray = obj.convert_frames_to_gray(frames);

        end

        function draw_inclusion_mask(obj)
            % Opens an interacive window that shows the image and allows the user to 
            % specify regions that the tracker algorithm should include in the
            % image. Users should right click on each rectangle they draw
            % and click on crop to save that region. Needs to be run
            % multiple times for multiple markers.

            underlay_image = obj.frames_gray(:,:,1);
            % In case the user wants to run this method multiple times, a
            % new crop mask can be added every time:
            if isempty(obj.inclusion_mask)
                f = figure('WindowState','maximized');[~,objectRegion_Include] = imcrop(underlay_image);close gcf;
                h=drawrectangle('Position',objectRegion_Include);
                obj.inclusion_mask = createMask(h,underlay_image);
            else
                underlay_image(obj.inclusion_mask)=0;
                f = figure('WindowState','maximized');[~,objectRegion_Include] = imcrop(underlay_image);close gcf;
                h=drawrectangle('Position',objectRegion_Include);
                obj.inclusion_mask = logical(obj.inclusion_mask + createMask(h,underlay_image));
            end

            
        end
        function points = tracking_overview(obj, frame_num, threshold_int)
            % Performs marker tracking for a single frame based on given
            % input parameters
            % Input args:
            % frame_num (int): the frame number in image stack
            % threshold_int (double): grayscale image intensity threshold
            % to filter out values below
            % filtration_low, filtration_high (int): minumum and maximum of
            % size (number of voxels) range for the marker(s) of interest

        
            % Store the frame of interest
            single_frame = obj.frames_gray(:,:,frame_num);
            % Create binary image based on threshold
            BW_image = single_frame<threshold_int;
            
            % Perform cleaning and filling on the binary image
            BW_image_cleaned = bwmorph(BW_image,'clean');
            BW_image_cleaned = bwmorph(BW_image_cleaned,'fill');

            % Perform closing operation removeing small holes in the foreground 
            se = strel('disk',1);
            after_cleanup = imclose(BW_image_cleaned,se);
            
            % Remove regions (blobs) in the image outside the range given
            % by the input filtration parameters
%             tracked_binary = bwareafilt(after_cleanup, [filtration_low filtration_high]);
            tracked_binary = after_cleanup;
            
            % Plot raw image, raw thresholded binary, image after cleanups,
            % and final image after blob removal
            figure
            subplot(2,2,1)
            imshow(obj.frames_gray(:,:,frame_num))
            title('Original grayscale')
            subplot(2,2,2)
            imshow(BW_image)
            title('Threshold Mask')
            subplot(2,2,3)
            imshow(after_cleanup)
            title('After cleanup')
            subplot(2,2,4)
            imshow(tracked_binary)
            title('Centroids of blobs')
            
            % Store blob centroids (more code can be added using the regionprops function to filter out
            % blobs not meeting certain criteria
           
            measurements = regionprops(tracked_binary, 'Centroid', 'Area');
            points = vertcat(measurements.Centroid);
            obj.initial_point_locs = points;
            
            % Plot the centroids on top of the binary image to verify the
            % correct points are discovered
            hold on 
            scatter(points(:,1),points(:,2),'filled')
            hold off
            obj.threshold_val = threshold_int;
        end
        function tracking_initiation(obj)
            % Same usage as the tracking_overview method; applies working
            % parameters and the inclusion mask on the first frame in stack


            % Store the frame of interest
            single_frame = obj.frames_gray(:,:,1);
            % Create binary image based on threshold
            BW_image = single_frame<obj.threshold_val;
            
            % Perform cleaning and filling on the binary image
            BW_image_cleaned = bwmorph(BW_image,'clean');
            BW_image_cleaned = bwmorph(BW_image_cleaned,'fill');

            % Perform closing operation removing small holes in the foreground 
            se = strel('disk',1);
            after_cleanup = imclose(BW_image_cleaned,se);
            % Filter out all points outside the inclusion_mask 
            after_cleanup(~obj.inclusion_mask)=0;
            measurements = regionprops(after_cleanup, 'Centroid', 'Area');
            points = vertcat(measurements.Centroid);
            obj.initial_point_locs = points;
            
            % Plot the centroids on top of the binary image to verify the
            % correct points are discovered
            figure
            imshow(after_cleanup)
            hold on 
            scatter(points(:,1),points(:,2),'filled')
            hold off
            title('Filtered initial binary frame with marker centroids')

        end
    
        function [tracked_x_log, tracked_y_log] = create_tracking_video(obj,vidname)
            % Tracks markers in the image across all the frames of the
            % frame stack and writes an mp4 video and gif file containing the image and the centroid(s) of the
            % marker(s)
            % Use input arguments that work across multiple frames by
            % experimenting with tracking_overview
            % Input args:
            % vidname (string): name of the file to be saved. The function saves an
            % mp4 and a gif with that filename

            % Outputs:
            % x and y coordinates (each an array with size num_frames*num_points) for the tracked markers' centroirds

            obj.tracked_x_log = zeros(length(obj.frames_gray),size(obj.initial_point_locs,1));
            obj.tracked_y_log = zeros(length(obj.frames_gray),size(obj.initial_point_locs,1));

            points_old = obj.initial_point_locs;
            videoPlayer = vision.VideoPlayer();
    
            
            video_object = VideoWriter(vidname,'MPEG-4');
            video_object.FrameRate = obj.original_frame_rate;
            open(video_object);

            for i = 1:size(obj.frames_gray,3)
                single_frame = obj.frames_gray(:,:,i);
                BW_image = single_frame<obj.threshold_val;
                
                
                BW_image_cleaned = bwmorph(BW_image,'clean');
                se = strel('disk',1);
                after_cleanup = imclose(BW_image_cleaned,se);
            
                measurements = regionprops(after_cleanup, 'Centroid', 'Area');
                points_new = vertcat(measurements.Centroid);

                if size(points_new,1)<size(obj.initial_point_locs,1)
                    
                    warning(append('Missed blob at #',string(i)))
                    points = points_old;
                else
                    points = points_new;
                    idx_array = zeros(size(obj.initial_point_locs,1),1);
    
                    for idx_i = 1:length(idx_array)
                        [~,idx_array(idx_i)] = min(sum((points - points_old(idx_i,:)).^2,2));
                    end
                    points = points(idx_array,:);
                    points_old = points;
                end
                points_transpose = points';
                obj.tracked_x_log(i,:) = points_transpose(1,:);
                obj.tracked_y_log(i,:) = points_transpose(2,:);    
                
                out = insertMarker(obj.frames_gray(:,:,i),points,'+','size',10);
                videoPlayer(out);
                writeVideo(video_object, out);
                [A,map] = rgb2ind(out,256);
                if i == 1
                    imwrite(A,map,append(vidname,'.gif'),'gif','LoopCount',Inf,'DelayTime',1/obj.original_frame_rate);
                else
                    imwrite(A,map,append(vidname,'.gif'),'gif','WriteMode','append','DelayTime',1/obj.original_frame_rate);
                end



            end
            close(video_object);
            tracked_x_log = obj.tracked_x_log;
            tracked_y_log = obj.tracked_y_log;
            
            end

    end
end
