local args = {...}

local GPU_PERIPHERAL = "tm_gpu"
local SPEAKER_PERIPHERAL = "top"
local IMAGE_PATH = args[1] or "frame.png"
local AUDIO_PATH = "audio.dfpwm"
local IMAGE_URL = "URL_HERE"
local AUDIO_URL = "URL_HERE"

local function findGPU()
if peripheral.isPresent(GPU_PERIPHERAL) then
    return peripheral.wrap(GPU_PERIPHERAL)
    end

    local peripherals = peripheral.getNames()
    for _, name in ipairs(peripherals) do
        if peripheral.getType(name) == "tm_gpu" then
            print("Found GPU at: " .. name)
            return peripheral.wrap(name)
            end
            end

            return nil
            end

            local function findSpeaker()
            local speakerName = SPEAKER_PERIPHERAL
            if peripheral.isPresent(speakerName) and peripheral.getType(speakerName) == "speaker" then
                print("Using speaker at: " .. speakerName)
                return peripheral.wrap(speakerName)
                else
                    error("No speaker found at '" .. speakerName .. "'! Audio playback requires a speaker on top of the computer.")
                    end
                    end

                    local function downloadFile(url, path)
                    local response = http.get(url)
                    if not response then
                        print("Failed to download from: " .. url)
                        return false
                        end

                        local data = response.readAll()
                        response.close()

                        local file = fs.open(path, "wb")
                        if not file then
                            print("Failed to open file for writing: " .. path)
                            return false
                            end
                            file.write(data)
                            file.close()

                            return true
                            end

                            -- Function to load PNG
                            local function loadPNG(filepath)
                            if not fs.exists(filepath) then
                                error("File not found: " .. filepath)
                                end

                                local file = fs.open(filepath, "rb")
                                if not file then
                                    error("Could not open file: " .. filepath)
                                    end

                                    local data = {}
                                    local byte = file.read()
                                    while byte do
                                        table.insert(data, byte)
                                        byte = file.read()
                                        end
                                        file.close()

                                        return data
                                        end

                                        -- Display image function (with scaling)
                                        local function displayImage(gpu, imagePath)
                                        print("Loading image: " .. imagePath)

                                        local pngData = loadPNG(imagePath)

                                        print("Decoding PNG...")
                                        local success, image = pcall(function()
                                        return gpu.decodeImage(table.unpack(pngData))
                                        end)

                                        if not success then
                                            error("Failed to decode PNG: " .. tostring(image))
                                            end

                                            local width = image.getWidth()
                                            local height = image.getHeight()
                                            print("Image size: " .. width .. "x" .. height)

                                            local w, h = gpu.getSize()
                                            print("Display size: " .. w .. "x" .. h)

                                            gpu.fill(0xFF000000)

                                            if width == w and height == h then
                                                print("Drawing image (no scaling needed)")
                                                local imageRef = image.ref()
                                                gpu.drawImage(0, 0, imageRef)
                                                else
                                                    print("Scaling image to fit display...")

                                                    local scaledImage = gpu.newImage(w, h)
                                                    local scaledGpu = scaledImage.gpuDraw()

                                                    local scaleX = w / width
                                                    local scaleY = h / height
                                                    local scale = math.min(scaleX, scaleY)

                                                    local scaledWidth = math.floor(width * scale)
                                                    local scaledHeight = math.floor(height * scale)

                                                    local x = math.floor((w - scaledWidth) / 2)
                                                    local y = math.floor((h - scaledHeight) / 2)

                                                    print("Scaled size: " .. scaledWidth .. "x" .. scaledHeight)
                                                    print("Position: " .. x .. ", " .. y)

                                                    scaledGpu.fill(0xFF000000)

                                                    local pixels = {image.getAsBuffer()}

                                                    local function getPixel(px, py)
                                                    if px >= 0 and px < width and py >= 0 and py < height then
                                                        return pixels[px + width * py + 1] or 0xFF000000
                                                        end
                                                        return 0xFF000000
                                                        end

                                                        local function lerpColor(c1, c2, t)
                                                        local a1 = bit.band(bit.brshift(c1, 24), 0xFF)
                                                        local r1 = bit.band(bit.brshift(c1, 16), 0xFF)
                                                        local g1 = bit.band(bit.brshift(c1, 8), 0xFF)
                                                        local b1 = bit.band(c1, 0xFF)

                                                        local a2 = bit.band(bit.brshift(c2, 24), 0xFF)
                                                        local r2 = bit.band(bit.brshift(c2, 16), 0xFF)
                                                        local g2 = bit.band(bit.brshift(c2, 8), 0xFF)
                                                        local b2 = bit.band(c2, 0xFF)

                                                        local a = math.floor(a1 + (a2 - a1) * t)
                                                        local r = math.floor(r1 + (r2 - r1) * t)
                                                        local g = math.floor(g1 + (g2 - g1) * t)
                                                        local b = math.floor(b1 + (b2 - b1) * t)

                                                        return bit.bor(bit.blshift(a, 24), bit.blshift(r, 16), bit.blshift(g, 8), b)
                                                        end

                                                        print("Applying bilinear interpolation...")
                                                        for sy = 0, scaledHeight - 1 do
                                                            for sx = 0, scaledWidth - 1 do
                                                                local srcX = (sx / scale)
                                                                local srcY = (sy / scale)

                                                                local x1 = math.floor(srcX)
                                                                local y1 = math.floor(srcY)
                                                                local x2 = x1 + 1
                                                                local y2 = y1 + 1

                                                                local fx = srcX - x1
                                                                local fy = srcY - y1

                                                                local c11 = getPixel(x1, y1)
                                                                local c21 = getPixel(x2, y1)
                                                                local c12 = getPixel(x1, y2)
                                                                local c22 = getPixel(x2, y2)

                                                                local c1 = lerpColor(c11, c21, fx)
                                                                local c2 = lerpColor(c12, c22, fx)

                                                                local finalColor = lerpColor(c1, c2, fy)

                                                                scaledImage.setRGB(x + sx, y + sy, finalColor)
                                                                end
                                                                if sy % 10 == 0 then
                                                                    term.write(".")
                                                                    end
                                                                    end
                                                                    print(" Done!")

                                                                    local scaledRef = scaledImage.ref()
                                                                    gpu.drawImage(0, 0, scaledRef)

                                                                    scaledImage.free()
                                                                    end

                                                                    print("Updating display...")
                                                                    gpu.sync()

                                                                    image.free()
                                                                    print("Image displayed successfully!")
                                                                    print("Used VRAM: " .. gpu.getUsedMemory() .. " / " .. gpu.getMaxMemory())
                                                                    end
                                                                    local function playAudioFile(speaker, filepath)
                                                                    if not fs.exists(filepath) then
                                                                        print("Audio file not found: " .. filepath)
                                                                        return false
                                                                        end

                                                                        print("Starting background audio playback...")
                                                                        local success = pcall(function()
                                                                        speaker.playSound(filepath, 1.0, 1.0, true)
                                                                        end)

                                                                        if not success then
                                                                            print("Failed to play audio file")
                                                                            return false
                                                                            end

                                                                            print("Audio playing in background!")
                                                                            return true
                                                                            end

                                                                            print("=== tbaggeroftheuk's simple video player")
                                                                            print()

                                                                            print("Searching for GPU peripheral...")
                                                                            local gpu = findGPU()
                                                                            if not gpu then
                                                                                error("No tm_gpu peripheral found! Please connect a GPU block.")
                                                                                end
                                                                                print("GPU found!")
                                                                                print()

                                                                                print("Searching for Speaker peripheral...")
                                                                                local speaker = findSpeaker()
                                                                                print("Speaker found!")
                                                                                print()

                                                                                print("Initializing display...")
                                                                                gpu.refreshSize()
                                                                                local w, h, blocks, res = gpu.getSize()
                                                                                print("Monitor configuration:")
                                                                                print("  Resolution: " .. w .. "x" .. h .. " pixels")
                                                                                print("  Blocks: " .. blocks .. " blocks")
                                                                                print("  Resolution multiplier: " .. res)
                                                                                print()

                                                                                local frameCount = 0
                                                                                local audioChunkCount = 0
                                                                                local lastAudioPlayTime = 0
                                                                                local AUDIO_CHUNK_DURATION = 60
                                                                                local audioPlaying = false

                                                                                print("Starting video playback...")
                                                                                print("Frame URL: " .. IMAGE_URL)
                                                                                print("Audio URL: " .. AUDIO_URL)
                                                                                print()

                                                                                while true do
                                                                                    frameCount = frameCount + 1

                                                                                    print("Frame " .. frameCount .. ": Downloading frame.png...")
                                                                                    if downloadFile(IMAGE_URL, IMAGE_PATH) then
                                                                                        displayImage(gpu, IMAGE_PATH)
                                                                                        else
                                                                                            print("Failed to download frame, skipping...")
                                                                                            end
                                                                                            local currentTime = os.epoch("utc") / 1000
                                                                                            if currentTime - lastAudioPlayTime >= AUDIO_CHUNK_DURATION then
                                                                                                audioChunkCount = audioChunkCount + 1
                                                                                                print("Downloading audio chunk " .. audioChunkCount .. "...")
                                                                                                if downloadFile(AUDIO_URL, AUDIO_PATH) then
                                                                                                    parallel.waitForAny(
                                                                                                        function()
                                                                                                        playAudioFile(speaker, AUDIO_PATH)
                                                                                                        end,
                                                                                                        function()
                                                                                                        os.sleep(0.1)
                                                                                                        end
                                                                                                    )
                                                                                                    lastAudioPlayTime = currentTime
                                                                                                    else
                                                                                                        print("Failed to download audio chunk")
                                                                                                        end
                                                                                                        end

                                                                                                        os.sleep(0)
                                                                                                        end
